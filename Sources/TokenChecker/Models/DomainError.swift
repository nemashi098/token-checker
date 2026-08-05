import Foundation

enum DomainError: Error, Equatable, LocalizedError, Sendable {
    case keychainTokenMissing
    case keychainReadFailed(status: Int32)
    case keychainCacheFailed(status: Int32)
    case anthropicUnauthorized
    case anthropicOAuthRefreshFailed
    case anthropicRateLimited(retryAfter: TimeInterval?)
    case anthropicHTTP(status: Int)
    case codexCLINotFound
    case codexProcessExited
    case codexRPCError(message: String)
    case decoding(String)
    case timeout
    case network(String)
    case invalidResponse
    case codexStartFailed(String)
    case codexDaemonTimeout
    case codexDaemonFailed(exitCode: Int32)
    case codexDaemonSpawnFailed(String)

    var errorDescription: String? {
        localizedDescription(language: .default)
    }

    func localizedDescription(language: AppLanguage) -> String {
        switch self {
        case .keychainTokenMissing:
            return L10n.tr("error.keychain_token_missing", language: language)
        case .keychainReadFailed(let status):
            return L10n.format("error.keychain_read_failed", language: language, Int(status))
        case .keychainCacheFailed(let status):
            return L10n.format("error.keychain_cache_failed", language: language, Int(status))
        case .anthropicUnauthorized:
            return L10n.tr("error.anthropic_unauthorized", language: language)
        case .anthropicOAuthRefreshFailed:
            return L10n.tr("error.anthropic_oauth_refresh_failed", language: language)
        case .anthropicRateLimited(let retryAfter):
            if let sec = retryAfter {
                let mins = max(1, Int((sec / 60).rounded()))
                return L10n.format("error.anthropic_rate_limited_with_retry", language: language, mins)
            }
            return L10n.tr("error.anthropic_rate_limited", language: language)
        case .anthropicHTTP(let status):
            return L10n.format("error.anthropic_http", language: language, status)
        case .codexCLINotFound:
            return L10n.tr("error.codex_cli_not_found", language: language)
        case .codexProcessExited:
            return L10n.tr("error.codex_process_exited", language: language)
        case .codexRPCError(let message):
            return L10n.format("error.codex_rpc", language: language, message)
        case .decoding(let detail):
            return L10n.format("error.decoding", language: language, detail)
        case .timeout:
            return L10n.tr("error.timeout", language: language)
        case .network(let detail):
            return L10n.format("error.network", language: language, detail)
        case .invalidResponse:
            return L10n.tr("error.invalid_response", language: language)
        case .codexStartFailed(let detail):
            return L10n.format("error.codex_start_failed", language: language, detail)
        case .codexDaemonTimeout:
            return L10n.tr("error.codex_daemon_timeout", language: language)
        case .codexDaemonFailed(let exitCode):
            return L10n.format("error.codex_daemon_failed", language: language, exitCode)
        case .codexDaemonSpawnFailed(let detail):
            return L10n.format("error.codex_daemon_spawn_failed", language: language, detail)
        }
    }
}
