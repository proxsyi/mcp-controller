import SwiftUI

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "General"
    case tailscale = "Tailscale"
    case updates = "Updates"
    var id: String { rawValue }
    var symbol: String {
        switch self { case .general: "switch.2"; case .tailscale: "globe"; case .updates: "arrow.triangle.2.circlepath" }
    }
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
                    ForEach(SettingsSection.allCases) { Label($0.rawValue, systemImage: $0.symbol).tag($0) }
                }.pickerStyle(.segmented).labelsHidden().frame(width: 360)
            }.padding(20)
            Divider()
            ZStack {
                switch selection {
                case .general: generalSettings.transition(.opacity.combined(with: .move(edge: .leading)))
                case .tailscale: TailscaleSettingsView().transition(.opacity)
                case .updates: updateSettings.transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .animation(AppMotion.standard(reduceMotion: reduceMotion), value: selection)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }.frame(width: 740, height: 560)
    }

    private var generalSettings: some View {
        ScrollView {
            VStack(spacing: 18) {
                settingsCard(title: "AI access", symbol: "person.badge.key") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Require one AI at a time on every server", isOn: $settings.oneAIOnly)
                            .fontWeight(.medium)
                            .onChange(of: settings.oneAIOnly) { _, enabled in model.applyGlobalOneAIPolicy(enabled) }
                        Text("Creates an exclusive gateway and Primary AI key for each server. Running servers apply changes after restart.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                settingsCard(title: "Overview", symbol: "server.rack") {
                    HStack(spacing: 18) {
                        metric("Configured", model.profiles.count, .secondary)
                        metric("Running", model.runningCount, .green)
                        metric("Failed", model.failedCount, .red)
                        metric("Tailscale", model.profiles.filter(\.tailscaleRouteEnabled).count, .blue)
                    }
                }
            }.padding(24)
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
                            if updates.isChecking || updates.isInstalling { ProgressView().controlSize(.small) }
                            else if updates.updateAvailable { Label("Update available", systemImage: "sparkles").font(.caption.weight(.semibold)).foregroundStyle(.blue) }
                            else { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                        }
                        Divider()
                        Text(updates.statusMessage.isEmpty ? "Updates are checked automatically after launch and every six hours." : updates.statusMessage)
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button("Check for Updates", systemImage: "arrow.triangle.2.circlepath") { updates.checkForUpdates() }
                                .disabled(updates.isChecking || updates.isInstalling)
                            if updates.updateAvailable {
                                Button("Update to \(updates.availableVersion ?? "latest")", systemImage: "arrow.down.circle.fill") { updates.installAvailableUpdate() }
                                    .buttonStyle(.borderedProminent)
                            }
                        }
                    }
                }
                settingsCard(title: "Release channel", symbol: "shippingbox") {
                    Label("Stable releases from proxsyi/mcp-controller", systemImage: "lock.shield").font(.callout)
                }
            }.padding(24)
        }
    }

    private var currentVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown" }
    private func settingsCard<Content: View>(title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) { Label(title, systemImage: symbol).font(.headline); content() }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 16))
    }
    private func metric(_ title: String, _ value: Int, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(value)").font(.title2.weight(.semibold)).foregroundStyle(color).contentTransition(.numericText())
            Text(title).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
