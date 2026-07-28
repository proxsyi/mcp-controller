import SwiftUI

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "General"
    case updates = "Updates"

    var id: String { rawValue }
    var symbol: String { self == .general ? "switch.2" : "arrow.triangle.2.circlepath" }
}

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var updates: UpdateManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection: SettingsSection = .general

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings").font(.title2.weight(.semibold))
                Spacer()
                Picker("Section", selection: $selection) {
                    ForEach(SettingsSection.allCases) { section in
                        Label(section.rawValue, systemImage: section.symbol).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 250)
            }
            .padding(20)

            Divider()

            ZStack {
                if selection == .general {
                    generalSettings
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                } else {
                    updateSettings
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .animation(AppMotion.standard(reduceMotion: reduceMotion), value: selection)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 680, height: 460)
    }

    private var generalSettings: some View {
        ScrollView {
            VStack(spacing: 18) {
                settingsCard(title: "AI access", symbol: "person.badge.key") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Require one AI at a time on every server", isOn: $settings.oneAIOnly)
                            .fontWeight(.medium)
                            .onChange(of: settings.oneAIOnly) { _, enabled in
                                withAnimation(AppMotion.standard(reduceMotion: reduceMotion)) {
                                    model.applyGlobalOneAIPolicy(enabled)
                                }
                            }
                        Text("Applies exclusive gateway access to every configured server and creates a Primary AI key when needed. Running servers use the new policy after their next restart.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if settings.oneAIOnly {
                            Label("One-AI access is configured globally", systemImage: "checkmark.shield.fill")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.green)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                }

                settingsCard(title: "Overview", symbol: "server.rack") {
                    HStack(spacing: 24) {
                        metric("Configured", value: model.profiles.count, color: .secondary)
                        metric("Running", value: model.runningCount, color: .green)
                        metric("Stopped", value: max(0, model.profiles.count - model.runningCount), color: .secondary)
                    }
                }
            }
            .padding(24)
        }
    }

    private var updateSettings: some View {
        ScrollView {
            VStack(spacing: 18) {
                settingsCard(title: "Software updates", symbol: "arrow.down.circle") {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("MCP Controller").fontWeight(.medium)
                                Text("Version \(currentVersion)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if updates.isChecking || updates.isInstalling {
                                ProgressView().controlSize(.small).transition(.scale.combined(with: .opacity))
                            } else if updates.updateAvailable {
                                Label("Update available", systemImage: "sparkles")
                                    .font(.caption.weight(.semibold)).foregroundStyle(.blue)
                                    .transition(.scale.combined(with: .opacity))
                            } else {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            }
                        }

                        Divider()

                        Text(updates.statusMessage.isEmpty ? "Updates are checked automatically after launch and every six hours." : updates.statusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .contentTransition(.opacity)

                        HStack {
                            Button("Check for Updates", systemImage: "arrow.triangle.2.circlepath") {
                                withAnimation(AppMotion.quick(reduceMotion: reduceMotion)) { updates.checkForUpdates() }
                            }
                            .disabled(updates.isChecking || updates.isInstalling)

                            if updates.updateAvailable {
                                Button("Update to \(updates.availableVersion ?? "latest")", systemImage: "arrow.down.circle.fill") {
                                    updates.installAvailableUpdate()
                                }
                                .buttonStyle(.borderedProminent)
                                .transition(.scale.combined(with: .opacity))
                            }
                        }
                    }
                }

                settingsCard(title: "Release channel", symbol: "shippingbox") {
                    Label("Stable releases from proxsyi/mcp-controller", systemImage: "lock.shield")
                        .font(.callout)
                }
            }
            .padding(24)
        }
        .animation(AppMotion.standard(reduceMotion: reduceMotion), value: updates.updateAvailable)
        .animation(AppMotion.quick(reduceMotion: reduceMotion), value: updates.isChecking)
        .animation(AppMotion.quick(reduceMotion: reduceMotion), value: updates.isInstalling)
    }

    private var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }

    private func settingsCard<Content: View>(title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: symbol).font(.headline)
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func metric(_ title: String, value: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(value)").font(.title2.weight(.semibold)).foregroundStyle(color).contentTransition(.numericText())
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
