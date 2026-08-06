@testable import TokenChecker
import Foundation
import Testing

// XCTest ではなく Swift Testing を使う（CodexExecutableDiscoveryTests と同じ理由）。
@MainActor
struct UsageTrendStoreTests {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    /// fiveHour だけを持つ Claude スナップショットを作る。
    private func snapshot(utilization: Double, resetsAt: Date, fetchedAt: Date) -> UsageSnapshot {
        let usage = ServiceUsage(
            fiveHour: RateLimit(utilization: utilization, resetsAt: resetsAt),
            weekly: nil,
            weeklySonnet: nil,
            scopedWeekly: []
        )
        return UsageSnapshot(claude: .success(usage), codex: nil, fetchedAt: fetchedAt)
    }

    /// 一定ペースでサンプルを流し込む。perHour は 1 時間あたりの消費割合。
    @discardableResult
    private func feed(
        store: UsageTrendStore,
        startUtilization: Double,
        perHour: Double,
        stepMinutes: Double,
        count: Int,
        resetsAt: Date
    ) -> [String: UsageTrend] {
        var result: [String: UsageTrend] = [:]
        for index in 0..<count {
            let elapsed = Double(index) * stepMinutes * 60
            let now = base.addingTimeInterval(elapsed)
            let utilization = startUtilization + perHour * (elapsed / 3600)
            result = store.update(
                snapshot: snapshot(utilization: utilization, resetsAt: resetsAt, fetchedAt: now),
                now: now
            )
        }
        return result
    }

    @Test func steadyBurnProducesRateAndDepletion() {
        let store = UsageTrendStore()
        // 6h 後リセット。枯渇は 5h 後（下記）なので「リセット前に枯渇」になる。
        // 5h ちょうどにすると枯渇時刻とリセット時刻が同時刻になり < 判定が偽になるので注意。
        let resetsAt = base.addingTimeInterval(6 * 3600)
        // 10%/時 で 30 分ぶん (7 サンプル・5 分間隔)
        let trends = feed(
            store: store, startUtilization: 0.5, perHour: 0.10,
            stepMinutes: 5, count: 7, resetsAt: resetsAt
        )

        guard let trend = trends["claude-five-hour"] else {
            Issue.record("claude-five-hour のトレンドが計算されていない")
            return
        }
        #expect(abs(trend.ratePerHour - 0.10) < 0.005)

        // 残り 45%（最終サンプル時点）を 10%/時 → 約 4.5 時間後に枯渇 = リセット(残り5.5h)より前
        #expect(trend.predictedDepletionAt != nil)
        guard let depletion = trend.predictedDepletionAt else { return }
        let lastSampleTime = base.addingTimeInterval(30 * 60)
        let hours = depletion.timeIntervalSince(lastSampleTime) / 3600
        #expect(abs(hours - 4.5) < 0.1)
        #expect(depletion < resetsAt)
    }

    @Test func flatUsageProducesNoTrend() {
        let store = UsageTrendStore()
        let trends = feed(
            store: store, startUtilization: 0.3, perHour: 0.0,
            stepMinutes: 5, count: 7, resetsAt: base.addingTimeInterval(3600)
        )
        #expect(trends["claude-five-hour"] == nil)
    }

    @Test func tooFewSamplesProducesNoTrend() {
        let store = UsageTrendStore()
        let trends = feed(
            store: store, startUtilization: 0.3, perHour: 0.2,
            stepMinutes: 6, count: 2, resetsAt: base.addingTimeInterval(3600)
        )
        #expect(trends["claude-five-hour"] == nil)
    }

    @Test func shortSpanProducesNoTrend() {
        let store = UsageTrendStore()
        // 4 サンプルでもスパン 3 分 (< 10 分) なら出さない
        let trends = feed(
            store: store, startUtilization: 0.3, perHour: 0.5,
            stepMinutes: 1, count: 4, resetsAt: base.addingTimeInterval(3600)
        )
        #expect(trends["claude-five-hour"] == nil)
    }

    @Test func resetClearsHistory() {
        let store = UsageTrendStore()
        let firstReset = base.addingTimeInterval(3600)
        feed(
            store: store, startUtilization: 0.8, perHour: 0.3,
            stepMinutes: 10, count: 4, resetsAt: firstReset
        )

        // リセット発生: utilization が下がり resetsAt が先へ跳ぶ → 履歴破棄で予測は消える
        let afterResetTime = base.addingTimeInterval(40 * 60)
        let afterReset = store.update(
            snapshot: snapshot(
                utilization: 0.01,
                resetsAt: firstReset.addingTimeInterval(5 * 3600),
                fetchedAt: afterResetTime
            ),
            now: afterResetTime
        )
        #expect(afterReset["claude-five-hour"] == nil)
    }

    @Test func slowBurnHoldsUntilReset() {
        let store = UsageTrendStore()
        let resetsAt = base.addingTimeInterval(2 * 3600)
        // 1%/時 × 残り 96% → 枯渇は 96 時間後 = リセット後（ただしホライズン内）
        let trends = feed(
            store: store, startUtilization: 0.04, perHour: 0.01,
            stepMinutes: 10, count: 4, resetsAt: resetsAt
        )
        let trend = trends["claude-five-hour"]
        #expect(trend != nil)
        if let depletion = trend?.predictedDepletionAt {
            #expect(depletion > resetsAt)
        }
    }
}
