import Foundation
@testable import TokenChecker
import Testing

/// リセット権（rateLimitResetCredits）の抽出テスト。
/// ペイロードは 2026-09-05 に実機の `account/rateLimits/read`（codex-cli 0.153.0-alpha.5）が
/// 返した構造そのまま（prolite・"Full reset" が 2 枚 available）。
@Suite struct CodexResetCreditsTests {

    private func decode(_ json: String) throws -> CodexRateLimitsDTO {
        try JSONDecoder().decode(CodexRateLimitsDTO.self, from: Data(json.utf8))
    }

    private let realPayload = """
    {
      "rateLimits": {
        "limitId": "codex", "limitName": null,
        "primary": {"usedPercent": 65, "windowDurationMins": 10080, "resetsAt": 1788779272},
        "secondary": null, "planType": "prolite"
      },
      "rateLimitsByLimitId": null,
      "rateLimitResetCredits": {
        "availableCount": 2,
        "credits": [
          {"id": "RateLimitResetCredit_a", "resetType": "codexRateLimits", "status": "available",
           "grantedAt": 1787357688, "expiresAt": 1789949688, "title": "Full reset",
           "description": "Thanks for using Codex! You've been granted one free rate limit reset."},
          {"id": "RateLimitResetCredit_b", "resetType": "codexRateLimits", "status": "available",
           "grantedAt": 1788488202, "expiresAt": 1791080202, "title": "Full reset",
           "description": "Thanks for using Codex! You've been granted one free rate limit reset."}
        ]
      }
    }
    """

    @Test func extractsCountAndEarliestExpiry() throws {
        let credits = try #require(try decode(realPayload).resetCredits())
        #expect(credits.availableCount == 2)
        #expect(credits.earliestExpiry == Date(timeIntervalSince1970: 1789949688))
    }

    @Test func flowsIntoServiceUsage() throws {
        let usage = CodexUsageProvider.usage(from: try decode(realPayload))
        #expect(usage.resetCredits?.availableCount == 2)
        #expect(usage.weekly?.percent == 65)
    }

    @Test func missingFieldMeansNoCredits() throws {
        // 旧 CLI はこのフィールドを返さない → nil で行ごと非表示
        let dto = try decode("""
        {"rateLimits": null, "rateLimitsByLimitId": null}
        """)
        #expect(dto.resetCredits() == nil)
        #expect(CodexUsageProvider.usage(from: dto).resetCredits == nil)
    }

    @Test func zeroCountMeansNoCredits() throws {
        let dto = try decode("""
        {"rateLimits": null, "rateLimitsByLimitId": null,
         "rateLimitResetCredits": {"availableCount": 0, "credits": []}}
        """)
        #expect(dto.resetCredits() == nil)
    }

    @Test func countOnlyWithoutDetailsHasNoExpiry() throws {
        // credits が null = 枚数しか分からない → 失効日は nil だが枚数は出す
        let dto = try decode("""
        {"rateLimits": null, "rateLimitsByLimitId": null,
         "rateLimitResetCredits": {"availableCount": 1, "credits": null}}
        """)
        let credits = try #require(dto.resetCredits())
        #expect(credits.availableCount == 1)
        #expect(credits.earliestExpiry == nil)
    }

    @Test func consumeResponseOutcomesDecode() throws {
        // スキーマ (codex 0.148 generate-json-schema) の 4 値がすべて enum に対応している
        for (raw, expected) in [
            ("reset", ResetCreditRedeemOutcome.reset),
            ("nothingToReset", .nothingToReset),
            ("noCredit", .noCredit),
            ("alreadyRedeemed", .alreadyRedeemed),
        ] {
            let dto = try JSONDecoder().decode(
                ConsumeResetCreditResponseDTO.self,
                from: Data(#"{"outcome":"\#(raw)"}"#.utf8)
            )
            #expect(ResetCreditRedeemOutcome(rawValue: dto.outcome) == expected)
            #expect(expected.localizationKey == "reset_credit.outcome.\(raw)")
        }
        #expect(ResetCreditRedeemOutcome(rawValue: "somethingNew") == nil)
    }

    @Test func consumeParamsEncodeWithoutCreditIdWhenNil() throws {
        // creditId を省略するとバックエンドが次の 1 枚を選ぶ。null でも省略でも可だが鍵名は camelCase 必須
        let data = try JSONEncoder().encode(ConsumeResetCreditParams(idempotencyKey: "k-1", creditId: nil))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["idempotencyKey"] as? String == "k-1")
        #expect(json["creditId"] == nil || json["creditId"] is NSNull)
    }

    @Test func codexProviderCanRedeemButClaudeCannot() {
        #expect((CodexUsageProvider() as UsageProvider) is ResetCreditRedeemer)
        #expect(!((ClaudeUsageProvider() as UsageProvider) is ResetCreditRedeemer))
    }

    @Test func redeemedCreditsDoNotContributeExpiry() throws {
        let dto = try decode("""
        {"rateLimits": null, "rateLimitsByLimitId": null,
         "rateLimitResetCredits": {"availableCount": 1, "credits": [
           {"id": "x", "resetType": "codexRateLimits", "status": "redeemed",
            "grantedAt": 1787000000, "expiresAt": 1787100000},
           {"id": "y", "resetType": "codexRateLimits", "status": "available",
            "grantedAt": 1788000000, "expiresAt": 1790000000}
         ]}}
        """)
        let credits = try #require(dto.resetCredits())
        #expect(credits.earliestExpiry == Date(timeIntervalSince1970: 1790000000))
    }
}
