import Foundation
import UserNotifications

final class UsageAlertNotifier: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    private let center = UNUserNotificationCenter.current()
    private var notifiedKeys = Set<String>()

    override init() {
        super.init()
        center.delegate = self
    }

    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    func evaluate(snapshot: UsageSnapshot, threshold: UsageAlertThreshold, language: AppLanguage) {
        for window in Self.windows(from: snapshot, language: language) {
            guard window.limit.remainingPercent <= threshold.rawValue else { continue }
            let key = "\(window.id)-\(Int(window.limit.resetsAt.timeIntervalSince1970))-\(threshold.rawValue)"
            guard notifiedKeys.insert(key).inserted else { continue }
            send(window: window, threshold: threshold, language: language)
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    private func send(window: AlertWindow, threshold: UsageAlertThreshold, language: AppLanguage) {
        let content = UNMutableNotificationContent()
        content.title = L10n.format(
            "alert.low_remaining.title",
            language: language,
            window.serviceName
        )
        content.body = L10n.format(
            "alert.low_remaining.body",
            language: language,
            window.windowName,
            window.limit.remainingPercent,
            threshold.rawValue
        )
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "tokenchecker-\(window.id)-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        center.add(request)
    }

    private static func windows(from snapshot: UsageSnapshot, language: AppLanguage) -> [AlertWindow] {
        var windows: [AlertWindow] = []
        if case .success(let usage) = snapshot.claude {
            windows.append(contentsOf: self.windows(
                from: usage,
                serviceID: "claude",
                serviceName: "Claude Code",
                language: language
            ))
        }
        if case .success(let usage) = snapshot.codex {
            windows.append(contentsOf: self.windows(
                from: usage,
                serviceID: "codex",
                serviceName: "Codex",
                language: language
            ))
        }
        return windows
    }

    private static func windows(
        from usage: ServiceUsage,
        serviceID: String,
        serviceName: String,
        language: AppLanguage
    ) -> [AlertWindow] {
        var windows: [AlertWindow] = []
        if let fiveHour = usage.fiveHour {
            windows.append(AlertWindow(
                id: "\(serviceID)-five-hour",
                serviceName: serviceName,
                windowName: L10n.tr("window.five_hour", language: language),
                limit: fiveHour
            ))
        }
        if let weekly = usage.weekly {
            windows.append(AlertWindow(
                id: "\(serviceID)-weekly",
                serviceName: serviceName,
                windowName: L10n.tr("window.weekly", language: language),
                limit: weekly
            ))
        }
        if let sonnet = usage.weeklySonnet {
            windows.append(AlertWindow(
                id: "\(serviceID)-weekly-sonnet",
                serviceName: serviceName,
                windowName: L10n.tr("window.weekly_sonnet", language: language),
                limit: sonnet
            ))
        }
        windows.append(contentsOf: usage.scopedWeekly.map { scoped in
            AlertWindow(
                id: "\(serviceID)-\(scoped.id)",
                serviceName: serviceName,
                windowName: scoped.title,
                limit: scoped.limit
            )
        })
        return windows
    }
}

private struct AlertWindow {
    let id: String
    let serviceName: String
    let windowName: String
    let limit: RateLimit
}
