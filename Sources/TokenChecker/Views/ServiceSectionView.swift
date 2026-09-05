import SwiftUI
import AppKit

/// Claude / Codex 1 サービスぶんの詳細セクション。
/// どのブランドのセクションかを表す。
enum ServiceBrand {
    case claude
    case codex

    /// ブランド色。ヘッダーのロゴ枠と、Claude マーク（template）の塗りに使う。
    /// Claude は公式のテラコッタ (#D97757)、Codex は公式ロゴの青紫に合わせている。
    var tint: Color {
        switch self {
        case .claude: Color(red: 0.85, green: 0.47, blue: 0.34)
        case .codex: Color(red: 0.42, green: 0.50, blue: 0.97)
        }
    }
}

/// リセット権の「使う」ボタンの配線。Codex セクションだけが持ち、Claude は nil。
struct ResetCreditRedeemControls {
    let state: ResetCreditRedeemState
    /// 確認ダイアログで OK された後に呼ばれる
    let redeem: () -> Void
    /// 結果表示を閉じる
    let dismiss: () -> Void
}

struct ServiceSectionView: View {
    let title: String
    let brand: ServiceBrand
    /// トレンド辞書 (UsageViewModel.trends) を引くためのウィンドウ ID 接頭辞 ("claude" / "codex")。
    let serviceID: String
    let result: Result<ServiceUsage, DomainError>?
    let trends: [String: UsageTrend]
    let language: AppLanguage
    let displayMode: UsageDisplayMode
    let loginAction: () -> Void
    var redeem: ResetCreditRedeemControls? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                BrandLogoView(brand: brand)
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                statusDot
                Button {
                    loginAction()
                } label: {
                    Image(systemName: "person.badge.key")
                }
                .buttonStyle(.borderless)
                .help(L10n.format("service.login.help", language: language, title))
            }

            switch result {
            case .none:
                loadingBlock
            case .some(.success(let usage)):
                usageBlock(usage)
            case .some(.failure(let err)):
                errorBlock(err)
            }
        }
        .padding(12)
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private func usageBlock(_ usage: ServiceUsage) -> some View {
        if let five = usage.fiveHour {
            limitRow(
                label: L10n.tr("window.five_hour", language: language),
                limit: five,
                prominent: true,
                showsReset: true,
                trend: trends["\(serviceID)-five-hour"]
            )
        } else if usage.weekly != nil {
            // 週次は取れているのに 5h が無い＝このプランに 5h 枠が存在しない
            // （Codex の prolite 等）。「データがありません」だとエラーに見えるため区別する
            noDataRow(L10n.tr("window.five_hour.not_offered", language: language))
        } else {
            noDataRow(L10n.tr("window.five_hour.no_data", language: language))
        }

        if let weekly = usage.weekly {
            limitRow(
                label: L10n.tr("window.weekly", language: language),
                limit: weekly,
                prominent: false,
                showsReset: true,
                trend: trends["\(serviceID)-weekly"]
            )
        }
        if let sonnet = usage.weeklySonnet {
            limitRow(
                label: L10n.tr("window.weekly_sonnet", language: language),
                limit: sonnet,
                prominent: false,
                showsReset: true,
                trend: trends["\(serviceID)-weekly-sonnet"]
            )
        }
        ForEach(usage.scopedWeekly) { scoped in
            limitRow(
                label: scoped.title,
                limit: scoped.limit,
                prominent: false,
                showsReset: true,
                trend: trends["\(serviceID)-\(scoped.id)"]
            )
        }
        if let credits = usage.resetCredits, credits.availableCount > 0 {
            resetCreditsRow(credits)
        }
        // 結果表示は枚数が 0 になって上のカードが消えても残す（最後の 1 枚を使った直後など）
        if let redeem {
            redeemStateRow(redeem)
        }
    }

    /// 「使う」の進行・結果を 1 行で出す。idle のときは何も描かない。
    @ViewBuilder
    private func redeemStateRow(_ redeem: ResetCreditRedeemControls) -> some View {
        switch redeem.state {
        case .idle:
            EmptyView()
        case .working:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(L10n.tr("reset_credit.working", language: language))
                Spacer()
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.primary.opacity(0.68))
        case .done(let outcome):
            redeemMessage(
                L10n.tr(outcome.localizationKey, language: language),
                icon: outcome == .reset ? "checkmark.circle.fill" : "info.circle.fill",
                color: outcome == .reset ? .green : .orange,
                dismiss: redeem.dismiss
            )
        case .failed(let err):
            redeemMessage(
                L10n.format("reset_credit.failed", language: language, err.localizedDescription(language: language)),
                icon: "exclamationmark.triangle.fill",
                color: .red,
                dismiss: redeem.dismiss
            )
        }
    }

    private func redeemMessage(_ text: String, icon: String, color: Color, dismiss: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Color.primary.opacity(0.5))
        }
        .padding(8)
        .background(color.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    /// 権利を消費する操作なので、必ず確認ダイアログを挟む。OK のときだけ true。
    private func confirmRedeem() -> Bool {
        let alert = NSAlert()
        alert.messageText = L10n.tr("reset_credit.confirm.title", language: language)
        alert.informativeText = L10n.tr("reset_credit.confirm.body", language: language)
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.tr("reset_credit.confirm.ok", language: language))
        alert.addButton(withTitle: L10n.tr("reset_credit.confirm.cancel", language: language))
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Codex の未使用リセット権。枠の行と同じ「ラベル＋大きい数字」の格で出すカード。
    /// 失効まで 7 日以内なら全体を警告色にして「使い忘れ」を防ぐ。
    private func resetCreditsRow(_ credits: ResetCredits) -> some View {
        let expiringSoon = credits.earliestExpiry.map { $0.timeIntervalSinceNow <= 7 * 24 * 3600 } ?? false
        let accent = expiringSoon ? Color.orange : brand.tint
        var subtitle = L10n.tr("reset_credit.subtitle", language: language)
        if let expiry = credits.earliestExpiry {
            let formatter = DateFormatter()
            formatter.locale = language.locale
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            subtitle += " · " + L10n.format("reset_credit.expires", language: language, formatter.string(from: expiry))
        }
        return HStack(alignment: .center, spacing: 10) {
            ZStack {
                Circle().fill(accent.opacity(0.18))
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(accent)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.tr("reset_credit.title", language: language))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(expiringSoon ? accent : Color.primary.opacity(0.62))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: 6)
            Text(L10n.format("reset_credit.count", language: language, credits.availableCount))
                .font(.system(size: 18, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(accent)
            if let redeem {
                let working: Bool = { if case .working = redeem.state { return true } else { return false } }()
                Button {
                    if confirmRedeem() { redeem.redeem() }
                } label: {
                    Text(L10n.tr("reset_credit.redeem", language: language))
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(accent)
                .disabled(working)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(accent.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(accent.opacity(0.35), lineWidth: 1)
        )
        .help(L10n.tr("reset_credit.help", language: language))
    }

    private func limitRow(
        label: String,
        limit: RateLimit,
        prominent: Bool,
        showsReset: Bool,
        trend: UsageTrend? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(label)
                    .font(.system(size: prominent ? 13 : 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer()
                Text("\(displayMode.primaryPercent(for: limit))%")
                    .font(.system(size: prominent ? 18 : 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(color(for: limit.utilization))
                Text(L10n.tr(displayMode.primaryMetricKey(), language: language))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.68))
            }
            ProgressBarView(
                value: displayMode.barValue(for: limit),
                height: prominent ? 7 : 5,
                tint: color(for: limit.utilization)
            )

            HStack(spacing: 5) {
                if showsReset {
                    resetBadge(limit.resetsAt)
                }
                Spacer()
                Text(L10n.format(
                    displayMode.secondaryMetricKey(),
                    language: language,
                    "\(displayMode.secondaryPercent(for: limit))%"
                ))
                    .lineLimit(1)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.primary.opacity(0.62))

            if let trend {
                trendRow(trend: trend, limit: limit)
            }
        }
    }

    /// 消費ペースの行。測定できる消費があるときだけ表示される。
    /// リセット前に枯渇する予測なら警告色で「あと◯◯で枯渇」を出す。
    private func trendRow(trend: UsageTrend, limit: RateLimit) -> some View {
        let depletesBeforeReset = trend.predictedDepletionAt.map { $0 < limit.resetsAt } ?? false
        let rate = L10n.format(
            "trend.per_hour",
            language: language,
            String(format: "%.1f", trend.ratePerHour * 100)
        )
        let status: String
        if depletesBeforeReset, let depletionAt = trend.predictedDepletionAt {
            status = L10n.format("trend.depletes_in", language: language, remainingLabel(to: depletionAt))
        } else {
            status = L10n.tr("trend.holds_until_reset", language: language)
        }

        return HStack(spacing: 4) {
            Image(systemName: depletesBeforeReset ? "exclamationmark.triangle.fill" : "chart.line.downtrend.xyaxis")
                .font(.system(size: 10, weight: .semibold))
            Text("\(rate) · \(status)")
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(depletesBeforeReset ? Color.red : Color.primary.opacity(0.55))
    }

    private func remainingLabel(to date: Date) -> String {
        let formatter = DateComponentsFormatter()
        var calendar = Calendar.current
        calendar.locale = language.locale
        formatter.calendar = calendar
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter.string(from: Date(), to: date) ?? "—"
    }

    private func noDataRow(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "clock.badge.questionmark")
                .font(.system(size: 12, weight: .medium))
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(2)
            Spacer()
        }
        .foregroundStyle(Color.primary.opacity(0.68))
        .padding(.vertical, 2)
    }

    private func errorBlock(_ err: DomainError) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(L10n.tr("error.fetch_failed", language: language))
                    .font(.system(size: 12, weight: .medium))
            }
            Text(err.localizedDescription(language: language))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private var statusDot: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 7, height: 7)
            .help(statusHelp)
    }

    private var loadingBlock: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(L10n.tr("status.loading", language: language))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.68))
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var cardBackground: some ShapeStyle {
        Color(nsColor: .controlBackgroundColor).opacity(0.88)
    }

    private var statusColor: Color {
        switch result {
        case .none:
            .secondary
        case .some(.success):
            .green
        case .some(.failure):
            .orange
        }
    }

    private var statusHelp: String {
        switch result {
        case .none:
            L10n.tr("status.loading", language: language)
        case .some(.success):
            "OK"
        case .some(.failure):
            L10n.tr("error.fetch_failed", language: language)
        }
    }

    private func color(for value: Double) -> Color {
        if value < 0.7 { return .green }
        if value < 0.85 { return .orange }
        return .red
    }

    private func resetBadge(_ date: Date) -> some View {
        let soon = isResetSoon(date)
        return HStack(spacing: 4) {
            Image(systemName: soon ? "hourglass" : "clock.arrow.circlepath")
                .font(.system(size: 11, weight: .semibold))
            Text(resetLabel(date))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .foregroundStyle(soon ? Color.orange : Color.primary.opacity(0.62))
        .padding(.horizontal, soon ? 6 : 0)
        .padding(.vertical, soon ? 2 : 0)
        .background {
            if soon {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.orange.opacity(0.14))
            }
        }
    }

    private func isResetSoon(_ date: Date) -> Bool {
        let remaining = date.timeIntervalSinceNow
        return remaining > 0 && remaining <= 90 * 60
    }

    private func resetLabel(_ date: Date) -> String {
        let now = Date()
        if date <= now { return L10n.tr("reset.soon", language: language) }
        let f = DateComponentsFormatter()
        var calendar = Calendar.current
        calendar.locale = language.locale
        f.calendar = calendar
        f.allowedUnits = [.hour, .minute]
        f.unitsStyle = .abbreviated
        let rel = f.string(from: now, to: date) ?? "—"
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        let absolute = formatter.string(from: date)
        return L10n.format("reset.remaining", language: language, rel, absolute)
    }
}

private struct BrandLogoView: View {
    let brand: ServiceBrand

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(brand.tint.opacity(0.14))
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(brand.tint.opacity(0.22), lineWidth: 1)

            // 公式ロゴ（BrandAssets）を優先し、素材が読めない場合だけ従来の手描き図形へ落とす。
            switch brand {
            case .claude:
                if let mark = BrandAssets.claudeMark {
                    Image(nsImage: mark)
                        .renderingMode(.template)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .foregroundStyle(brand.tint)
                        .frame(width: 17, height: 17)
                } else {
                    ClaudeBurstMark()
                        .stroke(brand.tint, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                        .frame(width: 16, height: 16)
                }
            case .codex:
                if let logo = BrandAssets.codexLogo {
                    // 素材自体に約 6% の透過マージンがあるので、枠いっぱい近くまで広げる
                    Image(nsImage: logo)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)
                } else {
                    OpenAINodeMark()
                        .stroke(brand.tint, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                        .frame(width: 18, height: 18)
                }
            }
        }
        .frame(width: 28, height: 28)
    }
}

private struct ClaudeBurstMark: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let inner = min(rect.width, rect.height) * 0.18
        let outer = min(rect.width, rect.height) * 0.48
        var path = Path()

        for index in 0..<12 {
            let angle = (Double(index) / 12.0) * .pi * 2.0
            let start = CGPoint(
                x: center.x + cos(angle) * inner,
                y: center.y + sin(angle) * inner
            )
            let end = CGPoint(
                x: center.x + cos(angle) * outer,
                y: center.y + sin(angle) * outer
            )
            path.move(to: start)
            path.addLine(to: end)
        }

        return path
    }
}

private struct OpenAINodeMark: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) * 0.34
        let points = (0..<6).map { index in
            let angle = (Double(index) / 6.0) * .pi * 2.0 - .pi / 6.0
            return CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
        }

        var path = Path()
        for index in 0..<6 {
            let current = points[index]
            let next = points[(index + 1) % 6]
            let control = CGPoint(
                x: center.x + (current.x - center.x) * 0.22 + (next.x - center.x) * 0.22,
                y: center.y + (current.y - center.y) * 0.22 + (next.y - center.y) * 0.22
            )
            path.move(to: current)
            path.addQuadCurve(to: next, control: control)
            path.move(to: current)
            path.addLine(to: center)
        }

        return path
    }
}
