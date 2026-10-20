import Foundation
@testable import TokenChecker
import Testing

/// モデル別枠（rateLimitsByLimitId）の抽出テスト。
/// ペイロードは 2026-08-17 に実機の `account/rateLimits/read` が返した構造そのまま
/// （prolite プラン・週次のみ・"codex_bengalfox" = GPT-5.3-Codex-Spark が同居）。
@Suite struct CodexScopedLimitsTests {

    private func decode(_ json: String) throws -> CodexRateLimitsDTO {
        try JSONDecoder().decode(CodexRateLimitsDTO.self, from: Data(json.utf8))
    }

    private let realPayload = """
    {
      "rateLimits": {
        "limitId": "codex", "limitName": null,
        "primary": {"usedPercent": 46, "windowDurationMins": 10080, "resetsAt": 1787281340},
        "secondary": null, "planType": "prolite"
      },
      "rateLimitsByLimitId": {
        "codex": {
          "limitId": "codex", "limitName": null,
          "primary": {"usedPercent": 46, "windowDurationMins": 10080, "resetsAt": 1787281340},
          "secondary": null, "planType": "prolite"
        },
        "codex_bengalfox": {
          "limitId": "codex_bengalfox", "limitName": "GPT-5.3-Codex-Spark",
          "primary": {"usedPercent": 0, "windowDurationMins": 10080, "resetsAt": 1787574205},
          "secondary": null, "planType": "prolite"
        }
      }
    }
    """

    @Test func extractsNamedModelLimit() throws {
        let scoped = try decode(realPayload).scopedWeeklyLimits()
        #expect(scoped.count == 1)
        #expect(scoped.first?.id == "codex_bengalfox")
        #expect(scoped.first?.title == "GPT-5.3-Codex-Spark")
        #expect(scoped.first?.limit.percent == 0)
    }

    @Test func mainLimitIsNotDuplicatedIntoScoped() throws {
        // "codex" はトップレベル rateLimits と同じ limitId なので scoped に含めない
        let scoped = try decode(realPayload).scopedWeeklyLimits()
        #expect(!scoped.contains { $0.id == "codex" })
    }

    @Test func weeklyStillComesFromMainSnapshot() throws {
        #expect(try decode(realPayload).weeklyRateLimit()?.percent == 46)
    }

    @Test func fiveHourIsNilWhenPlanHasNoFiveHourWindow() throws {
        // prolite プランは 300 分ウィンドウを返さない → nil が正しい
        #expect(try decode(realPayload).fiveHourRateLimit() == nil)
    }

    @Test func namelessEntriesUseServerIDAndBrokenEntriesAreSkipped() throws {
        let dto = try decode("""
        {
          "rateLimits": null,
          "rateLimitsByLimitId": {
            "a_no_name": {"limitId": "a_no_name", "limitName": null,
              "primary": {"usedPercent": 10, "windowDurationMins": 10080, "resetsAt": 1787000000},
              "secondary": null, "planType": null},
            "b_no_window": {"limitId": "b_no_window", "limitName": "Broken",
              "primary": null, "secondary": null, "planType": null},
            "c_missing_fields": {"limitId": "c_missing_fields", "limitName": "Partial",
              "primary": {"usedPercent": null, "windowDurationMins": 10080, "resetsAt": null},
              "secondary": null, "planType": null}
          }
        }
        """)
        #expect(dto.scopedWeeklyLimits().map(\.title) == ["a_no_name"])
    }

    @Test func scopedOrderIsStable() throws {
        let dto = try decode("""
        {
          "rateLimits": null,
          "rateLimitsByLimitId": {
            "z_model": {"limitId": "z_model", "limitName": "Z",
              "primary": {"usedPercent": 1, "windowDurationMins": 10080, "resetsAt": 1787000000},
              "secondary": null, "planType": null},
            "a_model": {"limitId": "a_model", "limitName": "A",
              "primary": {"usedPercent": 2, "windowDurationMins": 10080, "resetsAt": 1787000000},
              "secondary": null, "planType": null}
          }
        }
        """)
        #expect(dto.scopedWeeklyLimits().map(\.id) == ["a_model", "z_model"])
    }
}

@Suite struct CodexLatestModelCompatibilityTests {
    private func decode(_ json: String) throws -> CodexRateLimitsDTO {
        try JSONDecoder().decode(CodexRateLimitsDTO.self, from: Data(json.utf8))
    }

    @Test func futureModelIncludesBothWindowsAndServerName() throws {
        let dto = try decode("""
        {"rateLimits":{"limitId":"codex","primary":{"usedPercent":20,"windowDurationMins":10080,"resetsAt":2000000000}},
         "rateLimitsByLimitId":{"codex_future":{"limitId":"codex_future","limitName":"GPT-6.1-Astra",
           "primary":{"usedPercent":35,"windowDurationMins":300,"resetsAt":2000000000},
           "secondary":{"usedPercent":45,"windowDurationMins":10080,"resetsAt":2000000000}}}}
        """)
        let rows = dto.scopedWeeklyLimits()
        #expect(rows.map(\.title) == ["GPT-6.1-Astra", "GPT-6.1-Astra"])
        #expect(rows.map(\.windowDurationMins) == [300, 10080])
        #expect(Set(rows.map(\.id)).count == 2)
        #expect(dto.fiveHourRateLimit() == nil)
        #expect(dto.weeklyRateLimit()?.percent == 20)
    }

    @Test func mapOnlyCommonBucketIsNotRepeated() throws {
        let dto = try decode("""
        {"rateLimitsByLimitId":{"codex":{"limitId":"codex","limitName":"Codex",
          "primary":{"usedPercent":18,"windowDurationMins":10080,"resetsAt":2000000000}}}}
        """)
        #expect(dto.weeklyRateLimit()?.percent == 18)
        #expect(dto.scopedWeeklyLimits().isEmpty)
    }

    @Test func modelOnlyBucketsDoNotMasqueradeAsCommonUsage() throws {
        let dto = try decode("""
        {"rateLimitsByLimitId":{"new_model":{"limitName":"New model",
          "primary":{"usedPercent":18,"windowDurationMins":10080,"resetsAt":2000000000}}}}
        """)
        #expect(dto.weeklyRateLimit() == nil)
        #expect(dto.scopedWeeklyLimits().first?.limit.percent == 18)
    }

    @Test func supportsNewShortWindowDuration() throws {
        let dto = try decode("""
        {"rateLimits":{"limitId":"codex",
          "primary":{"usedPercent":31,"windowDurationMins":15,"resetsAt":2000000000}}}
        """)
        #expect(dto.fiveHourRateLimit()?.percent == 31)
        #expect(CodexUsageProvider.usage(from: dto).shortWindowDurationMins == 15)
    }
}
