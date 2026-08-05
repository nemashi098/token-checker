import SwiftUI
import AppKit

struct UsagePopoverView: View {
    @Bindable var viewModel: UsageViewModel
    @Bindable var languageStore: LanguageStore
    @ObservedObject var launchAtLogin: LaunchAtLoginStore

    private var language: AppLanguage { languageStore.selectedLanguage }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            ServiceSectionView(
                title: "Claude Code",
                brand: .claude,
                result: viewModel.snapshot.claude,
                language: language,
                displayMode: viewModel.displayMode,
                loginAction: { viewModel.openClaudeLogin() }
            )

            ServiceSectionView(
                title: "Codex",
                brand: .codex,
                result: viewModel.snapshot.codex,
                language: language,
                displayMode: viewModel.displayMode,
                loginAction: { viewModel.openCodexLogin() }
            )

            settingsBlock
            footer
        }
        .padding(14)
        .frame(width: 380)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Token Checker")
                .font(.system(size: 16, weight: .semibold))
            Spacer()
            Button {
                Task { await viewModel.refresh() }
            } label: {
                if viewModel.isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderless)
            .help(L10n.tr("footer.refresh_now", language: language))
        }
        .padding(.horizontal, 2)
    }

    private var settingsBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                settingPicker(
                    icon: "percent",
                    title: L10n.tr("settings.display_mode", language: language)
                ) {
                    Picker("", selection: $viewModel.displayMode) {
                        ForEach(UsageDisplayMode.allCases) { mode in
                            Text(mode.label(language: language)).tag(mode)
                        }
                    }
                }

                settingPicker(
                    icon: "timer",
                    title: L10n.tr("settings.refresh_interval", language: language)
                ) {
                    Picker("", selection: $viewModel.pollingInterval) {
                        ForEach(PollingInterval.allCases) { interval in
                            Text(interval.label(language: language)).tag(interval)
                        }
                    }
                }
            }

            HStack(spacing: 10) {
                settingPicker(
                    icon: "globe",
                    title: L10n.tr("settings.language", language: language)
                ) {
                    Picker("", selection: $languageStore.selectedLanguage) {
                        ForEach(AppLanguage.allCases) { option in
                            Text(L10n.tr(option.displayKey, language: option)).tag(option)
                        }
                    }
                }

                settingPicker(
                    icon: "bell.badge",
                    title: L10n.tr("settings.alert_threshold", language: language)
                ) {
                    Picker("", selection: $viewModel.alertThreshold) {
                        ForEach(UsageAlertThreshold.allCases) { threshold in
                            Text(threshold.label(language: language)).tag(threshold)
                        }
                    }
                }
                .disabled(!viewModel.notificationsEnabled)
                .opacity(viewModel.notificationsEnabled ? 1 : 0.62)
            }

            HStack {
                Image(systemName: "bell")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.7))
                    .frame(width: 16)
                Text(L10n.tr("settings.notifications", language: language))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.72))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { viewModel.notificationsEnabled },
                    set: { viewModel.setNotificationsEnabled($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
            }

            HStack {
                Image(systemName: "power")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.7))
                    .frame(width: 16)
                Text(L10n.tr("settings.launch_at_login", language: language))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.72))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { _ in launchAtLogin.toggle() }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
            }
        }
        .padding(.horizontal, 2)
        .padding(.top, 2)
    }

    private var footer: some View {
        HStack {
            if viewModel.snapshot.fetchedAt > .distantPast {
                Text(L10n.format(
                    "footer.updated_at",
                    language: language,
                    formattedTime(viewModel.snapshot.fetchedAt)
                ))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.66))
            }
            Spacer()
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Color.primary.opacity(0.7))
            .help(L10n.tr("footer.quit", language: language))
        }
        .padding(.horizontal, 2)
    }

    private func settingPicker<Content: View>(
        icon: String,
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.7))
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.66))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                content()
                    .labelsHidden()
                    .controlSize(.regular)
                    .fixedSize()
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
