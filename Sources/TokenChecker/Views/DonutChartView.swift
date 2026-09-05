import AppKit
import SwiftUI

/// 5h usage 1 本ぶんの円形プログレス。CCMeter の二重ドーナツから内側 7d を削除した版。
///
/// 中央にどのサービスかを示すロゴを表示する（メニューバーで Claude / Codex を一目で区別）。
/// ドーナツ中央に何を描くかを表すモード。
enum DonutCenter {
    case none
    case sfSymbol(String, scale: CGFloat = 0.48)
    case text(String, scale: CGFloat = 0.48)
    /// 公式ロゴなどの画像。`isTemplate` な画像は primary 色で塗り、それ以外は元の色のまま描く。
    /// 透過マージンを持つ素材は SF Symbol より大きめの scale が要る（ドーナツの穴は size − 2×lineWidth）。
    case image(NSImage, scale: CGFloat = 0.6)
}

struct DonutChartView: View {
    let value: Double   // 0.0 〜 1.0
    var size: CGFloat = 18
    var lineWidth: CGFloat = 4
    var center: DonutCenter = .none
    var tint: Color? = nil

    var body: some View {
        ZStack {
            // 背景のリング（未使用部分）
            Circle()
                .stroke(Color.gray.opacity(0.3), lineWidth: lineWidth)
                .frame(width: size - lineWidth, height: size - lineWidth)
            // 使用率に応じて色付き
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(
                    tint ?? color,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .frame(width: size - lineWidth, height: size - lineWidth)
                .rotationEffect(.degrees(-90))
            // 中央のロゴ
            centerContent
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private var centerContent: some View {
        switch center {
        case .none:
            EmptyView()
        case .sfSymbol(let name, let scale):
            Image(systemName: name)
                .font(.system(size: size * scale, weight: .semibold))
                .foregroundStyle(.primary)
        case .text(let str, let scale):
            Text(str)
                .font(.system(size: size * scale, weight: .bold, design: .monospaced))
                .foregroundStyle(.primary)
        case .image(let image, let scale):
            Image(nsImage: image)
                .renderingMode(image.isTemplate ? .template : .original)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(.primary)
                .frame(width: size * scale, height: size * scale)
        }
    }

    private var clamped: Double { min(max(value, 0), 1) }
    private var color: Color {
        if value < 0.7 { return .green }
        if value < 0.85 { return .orange }
        return .red
    }
}
