import Foundation

enum L10n {
    static func tr(_ key: String, language: AppLanguage) -> String {
        NSLocalizedString(key, tableName: nil, bundle: bundle(for: language), value: key, comment: "")
    }

    static func format(_ key: String, language: AppLanguage, _ arguments: CVarArg...) -> String {
        String(format: tr(key, language: language), locale: language.locale, arguments: arguments)
    }

    /// リソースバンドル内の同梱ファイル（ロゴ画像など lproj 以外）の URL を引く。
    /// 探索順は `resourceBundleCandidates` と同じなので、アプリ実行時と `swift test` の両方で届く。
    static func resourceURL(forResource name: String, withExtension ext: String) -> URL? {
        for bundle in resourceBundleCandidates {
            if let url = bundle.url(forResource: name, withExtension: ext) {
                return url
            }
        }
        return nil
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
        // Bundle(for:) 起点の候補は `swift test` 用。テスト実行時は Bundle.main が
        // テストランナー (swiftpm-testing-helper) になり、リソースバンドルは
        // .build/debug/ 直下（テストバンドルの隣）に置かれるため、
        // モジュール内クラスから逆引きしないと到達できない。
        let moduleBundleURL = Bundle(for: BundleToken.self).bundleURL
        let urls = [
            Bundle.main.resourceURL?.appendingPathComponent(bundleName),
            Bundle.main.bundleURL.appendingPathComponent(bundleName),
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/\(bundleName)"),
            moduleBundleURL.appendingPathComponent(bundleName),
            moduleBundleURL.deletingLastPathComponent().appendingPathComponent(bundleName),
        ].compactMap { $0 }

        let bundles = urls.compactMap { Bundle(url: $0) }
        return bundles.isEmpty ? [.main] : bundles
    }

    /// Bundle(for:) でモジュールの実体位置を引くためのアンカー。
    private final class BundleToken {}

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
