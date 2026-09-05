import AppKit

/// 公式ロゴ素材のローダー。
///
/// - `claude-mark.svg` … Claude の公式マーク（単色ベクター・約 2 KB）。template として
///   読み込み、色は描画側で付ける（メニューバーでは primary、ポップオーバーではブランド色）。
/// - `codex-logo.png`  … Codex の公式ロゴ（フルカラー・透過 PNG 104px・約 10 KB）。
///
/// どちらもリソースバンドル (TokenChecker_TokenChecker.bundle) から一度だけ読み込む。
/// 読み込みに失敗した場合は nil を返し、呼び出し側が従来の手描き図形へフォールバックする
/// （素材の欠落でアプリが起動しなくなることを避ける）。
enum BrandAssets {
    static let claudeMark: NSImage? = {
        guard let image = load(name: "claude-mark", ext: "svg") else { return nil }
        image.isTemplate = true
        return image
    }()

    static let codexLogo: NSImage? = load(name: "codex-logo", ext: "png")

    private static func load(name: String, ext: String) -> NSImage? {
        guard let url = L10n.resourceURL(forResource: name, withExtension: ext),
              let image = NSImage(contentsOf: url),
              image.isValid,
              image.size.width > 0
        else { return nil }
        return image
    }
}
