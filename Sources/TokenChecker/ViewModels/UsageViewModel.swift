import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class UsageViewModel {
    // applicationWillTerminate から MainActor を経由せず shutdown を呼べるよう
    // nonisolated 化する。providers 自体は immutable なので Sendable 違反は起きない。
    private nonisolated let claudeProvider: UsageProvider
    private nonisolated let codexProvider: UsageProvider
    private let alertNotifier: UsageAlertNotifier

    var snapshot: UsageSnapshot = .empty
    var isLoading: Bool = false
    var pollingInterval: PollingInterval {
        didSet { persistInterval() }
    }
    var displayMode: UsageDisplayMode {
        didSet { persistDisplayMode() }
    }
    private(set) var notificationsEnabled: Bool {
        didSet { persistNotificationsEnabled() }
    }
    var alertThreshold: UsageAlertThreshold {
        didSet {
            persistAlertThreshold()
            evaluateAlertsIfNeeded()
        }
    }

    init(
        claudeProvider: UsageProvider = ClaudeUsageProvider(),
        codexProvider: UsageProvider = CodexUsageProvider(),
        alertNotifier: UsageAlertNotifier = .init()
    ) {
        self.claudeProvider = claudeProvider
        self.codexProvider = codexProvider
        self.alertNotifier = alertNotifier
        self.pollingInterval = Self.loadPersistedInterval()
        self.displayMode = Self.loadPersistedDisplayMode()
        self.notificationsEnabled = Self.loadPersistedNotificationsEnabled()
        self.alertThreshold = Self.loadPersistedAlertThreshold()
    }

    /// `task(id: pollingInterval)` から駆動するメインループ。
    func runPollingLoop() async {
        await refresh()
        while !Task.isCancelled {
            do {
                try await Task.sleep(nanoseconds: UInt64(pollingInterval.seconds * 1_000_000_000))
            } catch {
                return
            }
            await refresh()
        }
    }

    /// アプリ終了時に子プロセスや永続接続を解放するためのクロージャを返す。
    ///
    /// `@MainActor` final class である自身を `@Sendable` クロージャがキャプチャできないため
    /// (Swift 6 strict-concurrency でエラー)、Sendable な providers だけを閉じ込めて公開する。
    /// AppDelegate.applicationWillTerminate からは MainActor を経由せず呼ばれる。
    nonisolated func makeShutdownHandler() -> @Sendable () async -> Void {
        let claude = claudeProvider
        let codex = codexProvider
        return {
            await claude.shutdown()
            await codex.shutdown()
        }
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        async let claude = fetchClaude()
        async let codex = fetchCodex()

        let (c, x) = await (claude, codex)
        let nextSnapshot = UsageSnapshot(claude: c, codex: x, fetchedAt: Date())
        snapshot = nextSnapshot
        evaluateAlertsIfNeeded(snapshot: nextSnapshot)
    }

    func setNotificationsEnabled(_ enabled: Bool) {
        guard enabled != notificationsEnabled else { return }
        if enabled {
            Task {
                let granted = await alertNotifier.requestAuthorization()
                notificationsEnabled = granted
                if granted {
                    evaluateAlertsIfNeeded()
                }
            }
        } else {
            notificationsEnabled = false
        }
    }

    private func fetchClaude() async -> Result<ServiceUsage, DomainError> {
        do {
            return .success(try await claudeProvider.fetch())
        } catch let err as DomainError {
            Logger.claude.error("fetch failed: \(err.localizedDescription)")
            return .failure(err)
        } catch {
            return .failure(.network(error.localizedDescription))
        }
    }

    private func fetchCodex() async -> Result<ServiceUsage, DomainError> {
        do {
            return .success(try await codexProvider.fetch())
        } catch let err as DomainError {
            Logger.codex.error("fetch failed: \(err.localizedDescription)")
            return .failure(err)
        } catch {
            return .failure(.network(error.localizedDescription))
        }
    }

    // MARK: - ログインボタン

    /// どのサービスを再ログインするかは enum 型で表現する。
    /// 任意文字列を AppleScript に渡せないようにしてインジェクションを「型として」不能にする。
    enum LoginTarget {
        case claude
        case codex

        var command: String {
            switch self {
            case .claude: return "claude login"
            case .codex:  return "codex login"
            }
        }
    }

    func openClaudeLogin() { spawnLogin(.claude) }
    func openCodexLogin()  { spawnLogin(.codex) }

    private func spawnLogin(_ target: LoginTarget) {
        let script = """
        tell application "Terminal"
            activate
            do script "\(target.command)"
        end tell
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        do { try process.run() } catch {
            Logger.ui.error("login spawn failed: \(error.localizedDescription)")
        }
    }

    // MARK: - 永続化

    private static let intervalKey = "pollingInterval"
    private static let displayModeKey = "usageDisplayMode"
    private static let notificationsEnabledKey = "usageNotificationsEnabled"
    private static let alertThresholdKey = "usageAlertThreshold"

    private static func loadPersistedInterval() -> PollingInterval {
        let raw = UserDefaults.standard.integer(forKey: intervalKey)
        return PollingInterval(rawValue: raw) ?? .default
    }

    private func persistInterval() {
        UserDefaults.standard.set(pollingInterval.rawValue, forKey: Self.intervalKey)
    }

    private static func loadPersistedDisplayMode() -> UsageDisplayMode {
        guard let raw = UserDefaults.standard.string(forKey: displayModeKey) else { return .default }
        return UsageDisplayMode(rawValue: raw) ?? .default
    }

    private func persistDisplayMode() {
        UserDefaults.standard.set(displayMode.rawValue, forKey: Self.displayModeKey)
    }

    private static func loadPersistedNotificationsEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: notificationsEnabledKey)
    }

    private func persistNotificationsEnabled() {
        UserDefaults.standard.set(notificationsEnabled, forKey: Self.notificationsEnabledKey)
    }

    private static func loadPersistedAlertThreshold() -> UsageAlertThreshold {
        let raw = UserDefaults.standard.integer(forKey: alertThresholdKey)
        return UsageAlertThreshold(rawValue: raw) ?? .default
    }

    private func persistAlertThreshold() {
        UserDefaults.standard.set(alertThreshold.rawValue, forKey: Self.alertThresholdKey)
    }

    private func evaluateAlertsIfNeeded(snapshot targetSnapshot: UsageSnapshot? = nil) {
        guard notificationsEnabled else { return }
        let rawLanguage = UserDefaults.standard.string(forKey: LanguageStore.languageKey)
        let language = rawLanguage.flatMap(AppLanguage.init(rawValue:)) ?? .default
        alertNotifier.evaluate(
            snapshot: targetSnapshot ?? snapshot,
            threshold: alertThreshold,
            language: language
        )
    }
}
