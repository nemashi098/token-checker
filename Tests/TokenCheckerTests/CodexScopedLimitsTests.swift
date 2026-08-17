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

    @Test func namelessOrBrokenEntriesAreSkipped() throws {
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
        #expect(dto.scopedWeeklyLimits().isEmpty)
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
