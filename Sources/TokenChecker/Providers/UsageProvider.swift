import Foundation

/// Claude / Codex / Mock を差し替え可能にするための抽象。
protocol UsageProvider: Sendable {
    /// 1 サービスぶんの使用状況を返す。失敗時は DomainError を throw。
    func fetch() async throws -> ServiceUsage

    /// 子プロセスや永続接続を持つ実装はここで解放する。
    /// アプリ終了時 (applicationWillTerminate) に同期的に呼ばれる前提。
    func shutdown() async
}

extension UsageProvider {
    /// stateless な実装向けのデフォルト。何もしない。
    func shutdown() async {}
}

/// リセット権を使える provider（現状 Codex のみ）。
/// ViewModel は `codexProvider as? ResetCreditRedeemer` で能力の有無を判定する。
protocol ResetCreditRedeemer: Sendable {
    /// 1 枚使う。`idempotencyKey` は操作ごとに UUID を新しく作る。
    func redeemResetCredit(idempotencyKey: String) async throws -> ResetCreditRedeemOutcome
}
