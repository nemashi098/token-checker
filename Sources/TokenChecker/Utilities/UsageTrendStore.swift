import Foundation

/// 消費ペース。utilization の履歴の傾きから「あとどれくらいで上限に達するか」を推定する。
struct UsageTrend: Equatable, Sendable {
    /// 1 時間あたりの消費割合 (0.021 = 2.1%/時)。UsageTrendStore は正の値のみ返す。
    let ratePerHour: Double
    /// このペースで 100% に達する予測時刻。ホライズン (14日) 内に達しない場合は nil。
    let predictedDepletionAt: Date?
}

/// ウィンドウ ID ごとに (時刻, utilization) の履歴を保持し、最小二乗法で消費ペースを出す。
///
/// 履歴はメモリのみ（再起動で消える。数サンプル貯まるまで予測は出さない設計なので問題ない）。
/// ID は UsageAlertNotifier の通知キーと同じ規約:
/// "claude-five-hour" / "claude-weekly" / "claude-weekly-sonnet" / "claude-<scoped.id>"、codex も同様。
@MainActor
final class UsageTrendStore {
    private struct Sample {
        let time: Date
        let utilization: Double
    }

    private struct History {
        var resetsAt: Date
        var samples: [Sample]
    }

    private var histories: [String: History] = [:]

    /// 傾き算出に使う直近サンプルの時間窓。
    static let lookback: TimeInterval = 60 * 60
    /// 予測に必要な最小サンプル数・最小時間スパン。起動直後に根拠の薄い予測を出さないため。
    static let minSamples = 3
    static let minSpan: TimeInterval = 10 * 60
    /// これ未満の傾きは「消費なし」とみなして予測を出さない (0.1%/時)。
    static let minRatePerHour = 0.001
    /// 枯渇予測を出す最長ホライズン。これより先は「実質枯渇しない」として nil。
    static let horizon: TimeInterval = 14 * 24 * 60 * 60

    /// スナップショット反映のたびに呼ぶ。履歴を更新し、計算できたウィンドウのトレンドを返す。
    func update(snapshot: UsageSnapshot, now: Date = Date()) -> [String: UsageTrend] {
        var result: [String: UsageTrend] = [:]
        var seen = Set<String>()

        for (serviceID, serviceResult) in [("claude", snapshot.claude), ("codex", snapshot.codex)] {
            guard case .success(let usage) = serviceResult else { continue }
            for entry in usage.windowLimits(serviceID: serviceID) {
                seen.insert(entry.id)
                record(id: entry.id, limit: entry.limit, now: now)
                if let trend = trend(id: entry.id, now: now) {
                    result[entry.id] = trend
                }
            }
        }

        // API から消えたウィンドウ（モデル別枠の廃止など）の履歴は捨てる。
        histories = histories.filter { seen.contains($0.key) }
        return result
    }

    private func record(id: String, limit: RateLimit, now: Date) {
        let utilization = max(0, limit.utilization)
        let sample = Sample(time: now, utilization: utilization)

        guard var history = histories[id] else {
            histories[id] = History(resetsAt: limit.resetsAt, samples: [sample])
            return
        }

        // リセット検知: resetsAt が動いた、または utilization が下がったら履歴を破棄する。
        // リセット直後の低い値と混ぜると「回復した」ように見える負の傾きが出るため。
        let resetJumped = abs(history.resetsAt.timeIntervalSince(limit.resetsAt)) > 60
        let utilizationDropped = history.samples.last.map { utilization < $0.utilization - 0.005 } ?? false
        if resetJumped || utilizationDropped {
            histories[id] = History(resetsAt: limit.resetsAt, samples: [sample])
            return
        }

        history.resetsAt = limit.resetsAt
        history.samples.append(sample)
        history.samples.removeAll { now.timeIntervalSince($0.time) > Self.lookback }
        histories[id] = history
    }

    private func trend(id: String, now: Date) -> UsageTrend? {
        guard let history = histories[id] else { return nil }
        let samples = history.samples
        guard samples.count >= Self.minSamples,
              let first = samples.first,
              let last = samples.last,
              last.time.timeIntervalSince(first.time) >= Self.minSpan else { return nil }

        // 最小二乗法で傾き (utilization / 秒) を求める。
        let t0 = first.time
        let xs = samples.map { $0.time.timeIntervalSince(t0) }
        let ys = samples.map(\.utilization)
        let n = Double(samples.count)
        let sumX = xs.reduce(0, +)
        let sumY = ys.reduce(0, +)
        let sumXX = xs.reduce(0) { $0 + $1 * $1 }
        let sumXY = zip(xs, ys).reduce(0) { $0 + $1.0 * $1.1 }
        let denominator = n * sumXX - sumX * sumX
        guard denominator > 0 else { return nil }
        let slopePerSecond = (n * sumXY - sumX * sumY) / denominator

        let ratePerHour = slopePerSecond * 3600
        guard ratePerHour >= Self.minRatePerHour else { return nil }

        let remaining = max(0, 1.0 - last.utilization)
        let secondsToDepletion = remaining / slopePerSecond
        let predicted: Date? = secondsToDepletion <= Self.horizon
            ? now.addingTimeInterval(secondsToDepletion)
            : nil
        return UsageTrend(ratePerHour: ratePerHour, predictedDepletionAt: predicted)
    }
}

extension ServiceUsage {
    /// 通知 (UsageAlertNotifier)・トレンド・表示で共通のウィンドウ ID と RateLimit の組。
    /// ID 規約を変えると通知の重複抑止キーとトレンド履歴が切れるので変更しないこと。
    func windowLimits(serviceID: String) -> [(id: String, limit: RateLimit)] {
        var result: [(id: String, limit: RateLimit)] = []
        if let fiveHour { result.append(("\(serviceID)-five-hour", fiveHour)) }
        if let weekly { result.append(("\(serviceID)-weekly", weekly)) }
        if let weeklySonnet { result.append(("\(serviceID)-weekly-sonnet", weeklySonnet)) }
        for scoped in scopedWeekly { result.append(("\(serviceID)-\(scoped.id)", scoped.limit)) }
        return result
    }
}
