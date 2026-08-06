import Foundation
@testable import TokenChecker
import Testing

// XCTest ではなく Swift Testing を使う（CodexExecutableDiscoveryTests と同じ理由）。
@MainActor
struct LanguageSelectionTests {
    @Test func languageStoreDefaultsToJapaneseWhenNoPreferenceExists() {
        let defaults = makeDefaults()

        let store = LanguageStore(defaults: defaults)

        #expect(store.selectedLanguage == .japanese)
    }

    @Test func languageStorePersistsSelectedLanguage() {
        let defaults = makeDefaults()
        let store = LanguageStore(defaults: defaults)

        store.selectedLanguage = .simplifiedChinese

        #expect(defaults.string(forKey: LanguageStore.languageKey) == "zh-Hans")
        #expect(LanguageStore(defaults: defaults).selectedLanguage == .simplifiedChinese)
    }

    @Test func localizationLookupUsesSelectedLanguageBundle() {
        #expect(L10n.tr("settings.refresh_interval", language: .japanese) == "更新間隔")
        #expect(L10n.tr("settings.refresh_interval", language: .english) == "Refresh interval")
        #expect(L10n.tr("settings.refresh_interval", language: .simplifiedChinese) == "刷新间隔")
    }

    @Test func localizationFormattingUsesSelectedLanguageBundle() {
        #expect(L10n.format("footer.updated_at", language: .english, "10:00") == "Updated: 10:00")
        #expect(L10n.format("footer.updated_at", language: .simplifiedChinese, "10:00") == "更新：10:00")
    }

    @Test func pollingIntervalLabelsUseSelectedLanguage() {
        #expect(PollingInterval.sec30.label(language: .japanese) == "30秒")
        #expect(PollingInterval.min5.label(language: .english) == "5 min")
        #expect(PollingInterval.min10.label(language: .simplifiedChinese) == "10 分钟")
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "TokenCheckerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
