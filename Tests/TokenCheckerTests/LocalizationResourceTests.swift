import Foundation
import Testing

// XCTest ではなく Swift Testing を使う（CodexExecutableDiscoveryTests と同じ理由）。
struct LocalizationResourceTests {
    private let languageCodes = ["ja", "en", "zh-Hans"]

    @Test func allLocalizationsHaveSameKeys() throws {
        let keySets = try Dictionary(uniqueKeysWithValues: languageCodes.map { code in
            (code, try localizationKeys(for: code))
        })

        let japaneseKeys = try #require(keySets["ja"])
        #expect(!japaneseKeys.isEmpty, "Japanese localization must not be empty")

        for code in languageCodes where code != "ja" {
            #expect(keySets[code] == japaneseKeys, "\(code) localization keys must match Japanese")
        }
    }

    @Test func infoPlistDeclaresJapaneseBaseAndSupportedLocalizations() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let plistURL = root.appending(path: "Resources/Info.plist")
        let data = try Data(contentsOf: plistURL)
        let plist = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])

        #expect(plist["CFBundleDevelopmentRegion"] as? String == "ja")
        #expect(plist["CFBundleLocalizations"] as? [String] == languageCodes)
    }

    private func localizationKeys(for code: String) throws -> Set<String> {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let url = root
            .appending(path: "Sources/TokenChecker/Resources")
            .appending(path: "\(code).lproj/Localizable.strings")
        let data = try Data(contentsOf: url)
        let plist = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
        return Set(plist.keys)
    }
}
