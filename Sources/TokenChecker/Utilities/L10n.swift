import Foundation

enum L10n {
    static func tr(_ key: String, language: AppLanguage) -> String {
        NSLocalizedString(key, tableName: nil, bundle: bundle(for: language), value: key, comment: "")
    }

    static func format(_ key: String, language: AppLanguage, _ arguments: CVarArg...) -> String {
        String(format: tr(key, language: language), locale: language.locale, arguments: arguments)
    }

    private static func bundle(for language: AppLanguage) -> Bundle {
        for bundle in resourceBundleCandidates {
            if let localized = localizedBundle(language: language, in: bundle) {
                return localized
            }
        }
        return .main
    }

    private static var resourceBundleCandidates: [Bundle] {
        let bundleName = "TokenChecker_TokenChecker.bundle"
        let urls = [
            Bundle.main.resourceURL?.appendingPathComponent(bundleName),
            Bundle.main.bundleURL.appendingPathComponent(bundleName),
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/\(bundleName)"),
        ].compactMap { $0 }

        let bundles = urls.compactMap { Bundle(url: $0) }
        return bundles.isEmpty ? [.main] : bundles
    }

    private static func localizedBundle(language: AppLanguage, in bundle: Bundle) -> Bundle? {
        let names = [language.resourceName, language.resourceName.lowercased()]
        for name in names {
            if let path = bundle.path(forResource: name, ofType: "lproj"),
               let localized = Bundle(path: path) {
                return localized
            }
        }
        return nil
    }
}
