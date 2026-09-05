import AppKit
import Foundation
@testable import TokenChecker
import Testing

/// 公式ロゴ素材が同梱され、読み込めて、重くならない範囲に収まっていることを確認する。
/// （素材が欠けても UI は手描き図形へフォールバックするが、黙って劣化させないためのテスト）
@Suite struct BrandAssetsTests {
    @Test func officialMarksAreBundledAndLoadable() throws {
        let claude = try #require(BrandAssets.claudeMark, "claude-mark.svg がリソースバンドルから読めない")
        #expect(claude.isTemplate, "Claude マークは template として塗り分ける前提")
        #expect(claude.size.width > 0 && claude.size.height > 0)

        let codex = try #require(BrandAssets.codexLogo, "codex-logo.png がリソースバンドルから読めない")
        #expect(!codex.isTemplate, "Codex ロゴはフルカラーのまま描く前提")
        #expect(codex.size.width > 0 && codex.size.height > 0)
    }

    @Test func assetsStayLightweight() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appending(path: "Sources/TokenChecker/Resources")
        let caps: [(name: String, maxBytes: Int)] = [
            ("claude-mark.svg", 8_000),
            ("codex-logo.png", 32_000),
        ]
        for entry in caps {
            let path = root.appending(path: entry.name).path
            let attrs = try FileManager.default.attributesOfItem(atPath: path)
            let size = try #require(attrs[.size] as? Int)
            #expect(size <= entry.maxBytes, "\(entry.name) は \(entry.maxBytes) バイト以下に保つ（現在 \(size)）")
        }
    }
}
