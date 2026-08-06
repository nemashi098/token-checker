@testable import TokenChecker
import Testing

// XCTest ではなく Swift Testing を使う（CodexExecutableDiscoveryTests と同じ理由）。
struct DomainErrorLocalizationTests {
    @Test func domainErrorsDefaultToJapaneseLocalizedErrorDescriptions() {
        #expect(DomainError.timeout.errorDescription == "通信がタイムアウトしました。")
    }

    @Test func domainErrorsCanRenderInSelectedLanguage() {
        #expect(
            DomainError.anthropicHTTP(status: 500).localizedDescription(language: .english)
                == "Anthropic API error (status 500)"
        )
        #expect(
            DomainError.decoding("bad payload").localizedDescription(language: .simplifiedChinese)
                == "响应解码失败：bad payload"
        )
    }

    @Test func codexDaemonErrorsRenderInSelectedLanguage() {
        #expect(
            DomainError.codexDaemonTimeout.localizedDescription(language: .english)
                == "codex app-server daemon start timed out (5s)"
        )
        #expect(
            DomainError.codexDaemonFailed(exitCode: 2).localizedDescription(language: .japanese)
                == "codex app-server daemon start に失敗しました (exit=2)"
        )
        #expect(
            DomainError.codexDaemonSpawnFailed("missing binary").localizedDescription(language: .simplifiedChinese)
                == "codex app-server daemon start 启动失败：missing binary"
        )
    }
}
