import Foundation
import CryptoKit
import Testing
@testable import TokenChecker

@Suite struct ClaudeCredentialCompatibilityTests {
    private func credentials(expiry: String = "4102444800000", token: String = "test-access") throws -> ClaudeOAuthCredentials {
        let data = Data("""
        {"claudeAiOauth":{"accessToken":"\(token)","refreshToken":"test-refresh",
        "expiresAt":\(expiry),"scopes":"user:profile user:inference","futureField":true}}
        """.utf8)
        return try KeychainPayload.credentials(from: data)
    }

    @Test func readsCurrentPayloadAndIgnoresNewFields() throws {
        let value = try credentials()
        #expect(value.accessToken == "test-access")
        #expect(value.scopes == ["user:profile", "user:inference"])
        #expect(value.expiresAt == Date(timeIntervalSince1970: 4102444800))
        #expect(!value.isExpired)
    }

    @Test(arguments: ["4102444800000", "4102444800", "\"4102444800000\""])
    func acceptsMillisecondSecondAndStringTimestamps(expiry: String) throws {
        #expect(try credentials(expiry: expiry).expiresAt == Date(timeIntervalSince1970: 4102444800))
    }

    @Test func emptyTokensRequireLogin() {
        #expect(throws: DomainError.keychainTokenMissing) { try credentials(token: "   ") }
    }

    @Test func absentExpiryRequiresRefresh() throws {
        #expect(try credentials(expiry: "null").isExpired)
    }

    @Test func defaultAndProfileStorageAreSeparate() {
        let home = "/tmp/example-home"
        let normal = ClaudeCredentialLocation(environment: [:], home: home)
        let profile = ClaudeCredentialLocation(environment: ["CLAUDE_CONFIG_DIR": "/tmp/work-profile"], home: home)
        let hash = SHA256.hash(data: Data("/tmp/work-profile".utf8)).map { String(format: "%02x", $0) }.joined().prefix(8)
        #expect(normal.serviceName == "Claude Code-credentials")
        #expect(normal.credentialsURL.path == home + "/.claude/.credentials.json")
        #expect(profile.serviceName == "Claude Code-credentials-" + hash)
        #expect(profile.credentialsURL.path == "/tmp/work-profile/.credentials.json")
    }

    @Test func secureStorageOverrideIncludingEmptyValueTakesPrecedence() {
        let location = ClaudeCredentialLocation(environment: ["CLAUDE_CONFIG_DIR": "/tmp/work", "CLAUDE_SECURESTORAGE_CONFIG_DIR": ""], home: "/tmp/example")
        #expect(location.serviceName == "Claude Code-credentials")
        #expect(location.directory.path == "/tmp/example/.claude")
    }

    @Test func canonicallyEquivalentProfileNamesUseSameKeychainItem() {
        let one = ClaudeCredentialLocation(environment: ["CLAUDE_CONFIG_DIR": "/tmp/caf\u{e9}"])
        let two = ClaudeCredentialLocation(environment: ["CLAUDE_CONFIG_DIR": "/tmp/cafe\u{301}"])
        #expect(one.serviceName == two.serviceName)
    }

    @Test func readsOfficialFileFallbackWhenProfileKeychainItemIsMissing() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let location = ClaudeCredentialLocation(environment: ["CLAUDE_CONFIG_DIR": directory.path])
        try Data("""
        {"claudeAiOauth":{"accessToken":"fixture-access","expiresAt":4102444800000}}
        """.utf8).write(to: location.credentialsURL)
        let actual = try await KeychainTokenSource(location: location).readCredentials()
        #expect(actual.accessToken == "fixture-access")
    }

    @Test func refreshFingerprintRemainsBoundToSourceCredentials() throws {
        let original = try credentials()
        var refreshed = try credentials(token: "new-test-access")
        #expect(original.fingerprint != refreshed.fingerprint)
        refreshed.sourceFingerprint = original.fingerprint
        #expect(original.fingerprint == refreshed.fingerprint)
        #expect(try credentials(token: "other-account").fingerprint != refreshed.sourceFingerprint)
    }
}

@Suite struct ClaudeModelCompatibilityTests {
    private func decode(_ json: String) throws -> AnthropicUsageDTO {
        try JSONDecoder().decode(AnthropicUsageDTO.self, from: Data(json.utf8))
    }

    @Test func discoversNewNamedModelsAndFallsBackToID() throws {
        let dto = try decode("""
        {"limits":[
          {"kind":"weekly_scoped","group":"weekly","percent":12,"resets_at":"2030-01-01T00:00:00Z",
           "scope":{"model":{"id":"claude-future-123","display_name":"Claude Future 123"}}},
          {"kind":"weekly_scoped","group":"weekly","percent":24,"resets_at":"2030-01-01T00:00:00Z",
           "scope":{"model":{"id":"claude-new-456"}}}
        ]}
        """)
        let rows = dto.scopedWeeklyRateLimits(defaultResetsAt: nil)
        #expect(rows.map(\.title) == ["Claude Future 123 only", "claude-new-456 only"])
        #expect(rows.map(\.limit.percent) == [12, 24])
    }

    @Test func discoversLegacyModelKeysWithoutVersionList() throws {
        let dto = try decode("""
        {"seven_day_opus":{"utilization":15,"resets_at":"2030-01-01T00:00:00Z"},
         "seven_day_future_model":{"utilization":27,"resets_at":"2030-01-01T00:00:00Z"},
         "seven_day_sonnet":{"utilization":10,"resets_at":"2030-01-01T00:00:00Z"},
         "seven_day_unused":null,"extra_usage":{"is_enabled":true}}
        """)
        #expect(dto.scopedWeeklyRateLimits(defaultResetsAt: nil).map(\.title) == ["Future Model only", "Opus only"])
        #expect(dto.sevenDaySonnet?.toRateLimit()?.percent == 10)
    }

    @Test func modernAndLegacyBucketsAreNotDuplicated() throws {
        let dto = try decode("""
        {"seven_day_opus":{"utilization":15,"resets_at":"2030-01-01T00:00:00Z"},
         "limits":[{"kind":"weekly_scoped","group":"weekly","percent":15,
           "scope":{"model":{"id":"claude-opus-99","display_name":"Opus 99"}}}]}
        """)
        let rows = dto.scopedWeeklyRateLimits(defaultResetsAt: Date(timeIntervalSince1970: 2000000000))
        #expect(rows.count == 1)
        #expect(rows.first?.title == "Opus 99 only")
    }
}
