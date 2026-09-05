import Foundation

/// `codex app-server` を介して Codex の rate limit を取得。
/// アプリのライフタイム中 1 プロセスを共有する。失敗時は再起動を試みる。
final class CodexUsageProvider: UsageProvider, @unchecked Sendable {
    private let client: CodexAppServerClient

    init(client: CodexAppServerClient = .init()) {
        self.client = client
    }

    func fetch() async throws -> ServiceUsage {
        do {
            try await client.start()
            return Self.usage(from: try await client.readRateLimits())
        } catch DomainError.codexProcessExited {
            // 一度落ちていたら再起動して再試行
            await client.stop()
            try await client.start()
            return Self.usage(from: try await client.readRateLimits())
        }
    }

    /// DTO → 表示用モデル。2 経路（通常／再起動後）で同じ変換を使う。
    static func usage(from dto: CodexRateLimitsDTO) -> ServiceUsage {
        ServiceUsage(
            fiveHour: dto.fiveHourRateLimit(),
            weekly: dto.weeklyRateLimit(),
            weeklySonnet: nil,
            scopedWeekly: dto.scopedWeeklyLimits(),
            resetCredits: dto.resetCredits()
        )
    }

    func shutdown() async {
        await client.stop()
    }
}

extension CodexUsageProvider: ResetCreditRedeemer {
    func redeemResetCredit(idempotencyKey: String) async throws -> ResetCreditRedeemOutcome {
        try await client.start()
        return try await client.consumeResetCredit(idempotencyKey: idempotencyKey)
    }
}
