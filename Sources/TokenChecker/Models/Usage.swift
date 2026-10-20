import Foundation

/// 1 つのレート制限ウィンドウ。
struct RateLimit: Equatable, Sendable {
    /// 0.0 〜 1.0+。1.0 で 100% 使用。たまに 1.0 を超えることがある（API 側仕様）。
    let utilization: Double
    /// ウィンドウがリセットされる時刻。
    let resetsAt: Date

    var percent: Int { Int((utilization * 100).rounded()) }
    var remainingFraction: Double { max(0, 1.0 - utilization) }
    var remainingPercent: Int { Int((remainingFraction * 100).rounded()) }
}

/// モデル別など、API が名前付きで返す追加のレート制限。
struct NamedRateLimit: Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let limit: RateLimit
    var windowDurationMins: Int64? = nil

    func displayTitle(language: AppLanguage) -> String {
        guard let minutes = windowDurationMins else { return title }
        let window: String
        switch minutes {
        case 300: window = L10n.tr("window.five_hour", language: language)
        case 10080: window = L10n.tr("window.weekly", language: language)
        default: window = L10n.format("window.minutes", language: language, Int(minutes))
        }
        return "\(title)（\(window)）"
    }
}

/// Codex が無料で付与する「レート制限リセット権」。使うと週次枠などがその場で全回復する。
/// 未使用の枚数と、そのうち最も早い失効日時（明細が無い場合は nil）。
struct ResetCredits: Equatable, Sendable {
    let availableCount: Int
    let earliestExpiry: Date?
}

/// リセット権を使った結果（`account/rateLimitResetCredit/consume` の outcome）。
enum ResetCreditRedeemOutcome: String, Decodable, Sendable, Equatable {
    /// 消費して、対象の枠がリセットされた
    case reset
    /// 今リセットできる枠がない（権利は消費されない）
    case nothingToReset
    /// 使える権利が残っていない
    case noCredit
    /// 同じ idempotencyKey の操作が既に完了している
    case alreadyRedeemed

    var localizationKey: String { "reset_credit.outcome.\(rawValue)" }
}

/// 「使う」ボタンの進行状態。ビューはこれを見て進捗・結果を出す。
enum ResetCreditRedeemState {
    case idle
    case working
    case done(ResetCreditRedeemOutcome)
    case failed(DomainError)
}

/// 1 サービス（Claude / Codex）の使用状況。
struct ServiceUsage: Equatable, Sendable {
    let fiveHour: RateLimit?
    let weekly: RateLimit?
    /// Claude のみ。Sonnet 専用 7d ウィンドウ。
    let weeklySonnet: RateLimit?
    /// API が返すモデル別の追加ウィンドウ（Codex は短期・週次の両方）。
    let scopedWeekly: [NamedRateLimit]
    /// Codex のみ。未使用のリセット権。無ければ nil（行ごと非表示）。
    var resetCredits: ResetCredits? = nil
    var shortWindowDurationMins: Int64? = nil
}

/// 取得結果。片方が失敗しても他方は表示できるよう個別に保持。
struct UsageSnapshot: Equatable, Sendable {
    let claude: Result<ServiceUsage, DomainError>?
    let codex: Result<ServiceUsage, DomainError>?
    let fetchedAt: Date

    static let empty = UsageSnapshot(claude: nil, codex: nil, fetchedAt: .distantPast)
}
