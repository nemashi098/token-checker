@testable import TokenChecker
import Testing

// XCTest ではなく Swift Testing を使う。XCTest はフル Xcode が必要で、
// Command Line Tools だけの環境では `swift test` がコンパイルできないため。
struct CodexExecutableDiscoveryTests {
    @Test func defaultCandidatesIncludeDesktopAppBundledCLIs() {
        let candidates = CodexAppServerClient.defaultCandidates(home: "/Users/tester")

        #expect(candidates.contains("/Applications/Codex.app/Contents/Resources/codex"))
        #expect(candidates.contains("/Users/tester/Applications/Codex.app/Contents/Resources/codex"))
        #expect(candidates.contains("/Applications/ChatGPT.app/Contents/Resources/codex"))
        #expect(candidates.contains("/Users/tester/Applications/ChatGPT.app/Contents/Resources/codex"))
    }
}
