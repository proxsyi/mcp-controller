import SwiftUI

private enum SettingsSection: String, CaseIterable, Identifiable {
    case app = "App"
    case remoteAccess = "Remote access"
    case updates = "Updates"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .app: return "switch.2"
        case .remoteAccess: return "globe"
        case .updates: return "arrow.triangle.2.circlepath"
        }
    }

    var storageValue: String {
        switch self {
        case .app: return "app"
        case .remoteAccess: return "remoteAccess"
        case .updates: return "updates"
        }
    }

    init?(storageValue: String) {
        switch storageValue {
        case "app": self = .app
        case "remoteAccess": self = .remoteAccess
        case "updates": self = .updates
        default: return nil
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var updates: UpdateManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection: SettingsSection = .app

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(selection.rawValue)
                    .font(.title2.weight(.semibold))
                Spacer()
                Picker("Section", selection: $selection) {
                    ForEach(SettingsSection.allCases) { Label($0.rawValue, systemImage: $0.symbol).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 380)
            }
            .padding(20)

            Divider()

            ZStack {
                switch selection {
                case .app: appSettings.transition(.opacity.combined(with: .move(edge: .leading)))
                case .remoteAccess: TailscaleSettingsView().transition(.opacity)
                case .updates: updateSettings.transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .animation(AppMotion.standard(reduceMotion: reduceMotion), value: selection)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 760, height: 560)
        .onAppear {
            selection = SettingsSection(storageValue: settings.preferredSettingsSection) ?? .app
        }
        .onChange(of: settings.preferredSettingsSection) { _, value in
            if let section = SettingsSection(storageValue: value), section != selection {
                selection = section
            }
        }
        .onChange(of: selection) { _, value in
            if settings.preferredSettingsSection != value.storageValue {
                settings.preferredSettingsSection = value.storageValue
            }
        }
    }

    private var appSettings: some View {
        ScrollView {
            VStack(spacing: 18) {
                settingsCard(title: "Overview", symbol: "server.rack") {
                    HStack(spacing: 18) {
                        metric("Configured", model.serverProfiles.count, .secondary)
                        metric("Running", model.runningCount, .green)
                        metric("Failed", model.failedCount, .red)
                        metric("Remote", model.serverProfiles.filter(\.tailscaleRouteEnabled).count, .blue)
                    }
                }

                settingsCard(title: "Default access behavior", symbol: "lock.shield") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Protect every server with one AI at a time", isOn: $settings.oneAIOnly)
                            .fontWeight(.medium)
                            .onChange(of: settings.oneAIOnly) { _, enabled in model.applyGlobalOneAIPolicy(enabled) }
                        Text("This is an app-wide default. Per-server remote client compatibility still stays in the Access tab.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
            }
            .padding(24)
        }
    }

    private var currentVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown" }
    private func settingsCard<Content: View>(title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: symbol).font(.headline)
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 16))
    }
    private func metric(_ title: String, _ value: Int, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(value)").font(.title2.weight(.semibold)).foregroundStyle(color).contentTransition(.numericText())
            Text(title).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
