@testable import TokenChecker
import XCTest

final class CodexExecutableDiscoveryTests: XCTestCase {
    func testDefaultCandidatesIncludeDesktopAppBundledCLIs() {
        let candidates = CodexAppServerClient.defaultCandidates(home: "/Users/tester")

        XCTAssertTrue(candidates.contains("/Applications/Codex.app/Contents/Resources/codex"))
        XCTAssertTrue(candidates.contains("/Users/tester/Applications/Codex.app/Contents/Resources/codex"))
        XCTAssertTrue(candidates.contains("/Applications/ChatGPT.app/Contents/Resources/codex"))
        XCTAssertTrue(candidates.contains("/Users/tester/Applications/ChatGPT.app/Contents/Resources/codex"))
    }
}
