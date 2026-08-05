import SwiftUI
import AppKit

/// メニューバーに表示する「2 つのドーナツ + %」。
///
/// SwiftUI ビューを `ImageRenderer` で NSImage に焼いて、
/// `Image(nsImage:)` でメニューバーに渡す。
/// `MenuBarExtra` の label に SwiftUI ビューを直接渡すとフォント等が制限されるため。
struct MenuBarLabel: View {
    let viewModel: UsageViewModel

    var body: some View {
        if let image = renderedImage {
            Image(nsImage: image)
        } else {
            Text("TC ⏳")
        }
    }

    private var renderedImage: NSImage? {
        let claude = limit(from: viewModel.snapshot.claude)
        let codex = limit(from: viewModel.snapshot.codex)
        let mode = viewModel.displayMode
        let content = HStack(spacing: 6) {
            HStack(spacing: 3) {
                DonutChartView(
                    value: claude.map(mode.barValue(for:)) ?? 0,
                    size: 20,
                    lineWidth: 3,
                    center: .sfSymbol("sparkles", scale: 0.48),
                    tint: claude.map { color(for: $0.utilization) }
                )
                Text(percentLabel(claude, mode: mode))
                    .font(.system(size: 11, weight: .semibold))
            }
            HStack(spacing: 3) {
                DonutChartView(
                    value: codex.map(mode.barValue(for:)) ?? 0,
                    size: 20,
                    lineWidth: 3,
                    center: .sfSymbol("terminal.fill", scale: 0.48),
                    tint: codex.map { color(for: $0.utilization) }
                )
                Text(percentLabel(codex, mode: mode))
                    .font(.system(size: 11, weight: .semibold))
            }
        }
        .padding(.horizontal, 2)
        .foregroundStyle(Color.primary)

        let renderer = ImageRenderer(content: content)
        // ビットマップは高 DPI で焼いておく．image.size には触らない
        // （触ると point 単位として誤認されて表示サイズまで縮んでしまう）．
        let maxScale = NSScreen.screens.map(\.backingScaleFactor).max() ?? 2
        renderer.scale = max(maxScale, 3)
        guard let image = renderer.nsImage else { return nil }
        image.isTemplate = false
        return image
    }

    private func limit(from result: Result<ServiceUsage, DomainError>?) -> RateLimit? {
        guard case .success(let usage) = result else { return nil }
        return usage.fiveHour ?? usage.weekly
    }

    private func percentLabel(_ limit: RateLimit?, mode: UsageDisplayMode) -> String {
        guard let limit else { return "--%" }
        // メニューバーは横幅が限られるため 100% で頭打ちにし、超過は "+" で示す。
        // RateLimit.utilization は仕様上 1.0 を超えうる（Anthropic API 既知挙動）。
        let raw = mode == .used ? limit.utilization : limit.remainingFraction
        if raw > 1.0 { return "100%+" }
        let clamped = max(0, raw)
        return "\(Int((clamped * 100).rounded()))%"
    }

    private func color(for value: Double) -> Color {
        if value < 0.7 { return .green }
        if value < 0.85 { return .orange }
        return .red
    }
}
