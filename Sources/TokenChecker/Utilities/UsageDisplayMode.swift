import Foundation

enum UsageDisplayMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case remaining
    case used

    var id: String { rawValue }

    func label(language: AppLanguage) -> String {
        switch self {
        case .remaining: L10n.tr("display.remaining", language: language)
        case .used: L10n.tr("display.used", language: language)
        }
    }

    func primaryPercent(for limit: RateLimit) -> Int {
        switch self {
        case .remaining: limit.remainingPercent
        case .used: limit.percent
        }
    }

    func primaryMetricKey() -> String {
        switch self {
        case .remaining: "metric.remaining"
        case .used: "metric.used"
        }
    }

    func secondaryMetricKey() -> String {
        switch self {
        case .remaining: "metric.used_percent"
        case .used: "metric.remaining_percent"
        }
    }

    func secondaryPercent(for limit: RateLimit) -> Int {
        switch self {
        case .remaining: limit.percent
        case .used: limit.remainingPercent
        }
    }

    func barValue(for limit: RateLimit) -> Double {
        switch self {
        case .remaining: limit.remainingFraction
        case .used: limit.utilization
        }
    }

    static let `default`: UsageDisplayMode = .remaining
}

enum UsageAlertThreshold: Int, CaseIterable, Identifiable, Codable, Sendable {
    case five = 5
    case ten = 10
    case twenty = 20
    case thirty = 30

    var id: Int { rawValue }

    func label(language: AppLanguage) -> String {
        L10n.format("alert.threshold.percent", language: language, rawValue)
    }

    static let `default`: UsageAlertThreshold = .twenty
}
