import SwiftUI
import AppKit

struct ExposureSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var profile: ServerProfile
    let phase: RuntimePhase
    let persistLiveChange: (ServerProfile) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dnsName = ""
    @State private var dnsRefreshToken = UUID()
    @State private var mountPathText = ""
    @FocusState private var routePathIsFocused: Bool

    var body: some View {
        VStack(spacing: 16) {
            remoteAccessCard
            remoteCompatibilityCard
            GatewayAccessView(profile: $profile, isRunning: phase.isActive)
        }
        .animation(AppMotion.standard(reduceMotion: reduceMotion), value: profile.tailscaleRouteEnabled)
        .onAppear {
            mountPathText = profile.mountPath
            refreshDNS()
        }
        .onChange(of: profile.tailscalePath) { _, _ in refreshDNS() }
        .onChange(of: profile.tailscaleRouteEnabled) { _, _ in refreshDNS() }
        .onChange(of: profile.exposureMode) { _, _ in refreshDNS() }
        .onChange(of: profile.mountPath) { _, value in
            if !routePathIsFocused { mountPathText = value }
        }
        .onChange(of: routePathIsFocused) { _, focused in
            if !focused { commitMountPath() }
        }
    }

    private var isLiveFunnelRouteLocked: Bool {
        model.tailscaleFunnelRunning && profile.exposureMode == .funnel
    }

    private var remoteAccessCard: some View {
        ContentCard(title: "Remote access", symbol: "globe") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Remote route").fontWeight(.medium)
                        Text(profile.tailscaleRouteEnabled
                             ? "These settings directly control this server’s remote route."
                             : "Turn this on to give the server a Tailscale route.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("Remote access", isOn: remoteAccessBinding).labelsHidden()
                }

                if profile.tailscaleRouteEnabled {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                        GridRow {
                            Text("Audience").foregroundStyle(.secondary)
                            Picker("Audience", selection: exposureModeBinding) {
                                Text("Tailnet only").tag(ExposureMode.tailnet)
                                Text("Public Funnel").tag(ExposureMode.funnel)
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .disabled(isLiveFunnelRouteLocked)
                        }
                        GridRow {
                            Text("HTTPS port").foregroundStyle(.secondary)
                            Picker("HTTPS port", selection: publicPortBinding) {
                                ForEach([443, 8443, 10000], id: \.self) { Text(String($0)).tag($0) }
                            }
                            .labelsHidden()
                            .frame(width: 120)
                            .disabled(isLiveFunnelRouteLocked)
                        }
                        GridRow {
                            Text("Route path").foregroundStyle(.secondary)
                            TextField("/mcp/server", text: $mountPathText)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.subheadline, design: .monospaced))
                                .focused($routePathIsFocused)
                                .onSubmit { commitMountPath() }
                                .disabled(isLiveFunnelRouteLocked)
                        }
                        GridRow {
                            Text("Remote URL").foregroundStyle(.secondary)
                            HStack(spacing: 8) {
                                Text(publicAddress ?? "Address available when Tailscale is connected")
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                    .foregroundStyle(publicAddress == nil ? .secondary : .primary)
                                    .lineLimit(1)
                                Spacer()
                                Button("Copy", systemImage: "square.on.square") {
                                    guard let publicAddress else { return }
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(publicAddress, forType: .string)
                                }
                                .controlSize(.small)
                                .disabled(publicAddress == nil)
                            }
                        }
                    }

                    Text(isLiveFunnelRouteLocked
                         ? "Stop the shared Funnel in Settings before editing this live public route."
                         : "Route changes are applied when you press Return or leave the route path field.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("This server is currently local only.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var remoteCompatibilityCard: some View {
        ContentCard(title: "Remote client compatibility", symbol: "bolt.horizontal.circle") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Compatibility mode").fontWeight(.medium)
                        Text("Keeps remote access, route protection, and the default key aligned for this server.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("Remote client compatibility", isOn: compatibilityBinding)
                        .labelsHidden()
                }

                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                    GridRow { Text("Status").foregroundStyle(.secondary); statusLine }
                    GridRow {
                        Text("Remote access").foregroundStyle(.secondary)
                        Text(profile.tailscaleRouteEnabled ? audienceLabel : "Off")
                    }
                    GridRow {
                        Text("Route protection").foregroundStyle(.secondary)
                        Text(profile.exclusiveGatewayEnabled ? "Access key required" : "Direct")
                    }
                    GridRow {
                        Text("Default key").foregroundStyle(.secondary)
                        Text(defaultKeyLabel)
                    }
                }

                if phase.isActive {
                    Text("Stop the server before changing compatibility mode.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var publicAddress: String? {
        guard profile.tailscaleRouteEnabled, profile.exposureMode != .disabled else { return nil }
        return model.remoteURL(for: profile)
    }

    private var audienceLabel: String {
        switch profile.exposureMode {
        case .disabled: return "Off"
        case .tailnet: return "Tailnet only"
        case .funnel: return "Public Funnel"
        }
    }

    private var defaultKeyLabel: String {
        if let credential = profile.clientCredentials.first(where: { $0.name == "Primary AI" }) { return credential.name }
        return profile.clientCredentials.first?.name ?? "Will create Primary AI"
    }

    private var statusLine: some View {
        HStack(spacing: 8) {
            Circle().fill(compatibilityColor).frame(width: 8, height: 8)
            Text(compatibilityTitle)
                .foregroundStyle(compatibilityColor)
                .fontWeight(.medium)
        }
    }

    private var compatibilityTitle: String {
        if !profile.remoteClientCompatibilityEnabled { return "Off" }
        if !profile.tailscaleRouteEnabled || profile.exposureMode == .disabled { return "Needs remote access" }
        if phase.isFailed { return "Needs attention" }
        if dnsName.isEmpty { return "Waiting for Tailscale" }
        return phase.isActive ? "Configured" : "Ready when running"
    }

    private var compatibilityColor: Color {
        if !profile.remoteClientCompatibilityEnabled { return .secondary }
        if phase.isFailed { return .red }
        if !profile.tailscaleRouteEnabled || profile.exposureMode == .disabled || dnsName.isEmpty { return .orange }
        return phase.isActive ? .green : .secondary
    }

    private var remoteAccessBinding: Binding<Bool> {
        Binding(get: { profile.tailscaleRouteEnabled }, set: { applyRemoteAccess(enabled: $0) })
    }

    private var exposureModeBinding: Binding<ExposureMode> {
        Binding(
            get: { profile.exposureMode },
            set: { value in
                var updated = profile
                updated.exposureMode = value
                applyRouteConfigurationChange(updated)
            }
        )
    }

    private var publicPortBinding: Binding<Int> {
        Binding(
            get: { profile.publicPort },
            set: { value in
                var updated = profile
                updated.publicPort = value
                applyRouteConfigurationChange(updated)
            }
        )
    }

    private var compatibilityBinding: Binding<Bool> {
        Binding(
            get: { profile.remoteClientCompatibilityEnabled },
            set: { enabled in
                var updated = profile
                updated.remoteClientCompatibilityEnabled = enabled
                if enabled {
                    updated.exclusiveGatewayEnabled = true
                    if updated.clientCredentials.isEmpty { updated.clientCredentials.append(.generate(name: "Primary AI")) }
                    if updated.gatewayPort == updated.localPort {
                        updated.gatewayPort = model.nextAvailableGatewayPort(startingAt: updated.gatewayPort + 1)
                    }
                    if updated.exposureMode == .disabled { updated.exposureMode = .tailnet }
                    if updated.normalizedMountPath == "/" { updated.mountPath = model.uniqueMountPath(for: updated.name) }
                    profile = updated
                    if !updated.tailscaleRouteEnabled { applyRemoteAccess(enabled: true) }
                } else {
                    profile = updated
                }
                refreshDNS()
            }
        )
    }

    private func applyRemoteAccess(enabled: Bool) {
        if enabled {
            var updated = profile
            updated.tailscaleRouteEnabled = true
            if updated.exposureMode == .disabled { updated.exposureMode = .tailnet }
            if updated.normalizedMountPath == "/" { updated.mountPath = model.uniqueMountPath(for: updated.name) }
            if updated.tailscalePath.isEmpty || !TailscaleRouteService.isCLIAvailable(at: updated.tailscalePath) {
                updated.tailscalePath = TailscaleRouteService.defaultCLIPath
            }
            if model.startTailscaleRoute(updated) {
                profile = updated
                mountPathText = updated.mountPath
                persistLiveChange(updated)
            }
        } else {
            let current = profile
            var updated = profile
            updated.tailscaleRouteEnabled = false
            if model.stopTailscaleRoute(current) {
                profile = updated
                persistLiveChange(updated)
            }
        }
        refreshDNS()
    }

    @discardableResult
    private func applyRouteConfigurationChange(_ updated: ServerProfile) -> Bool {
        if updated.tailscaleRouteEnabled {
            guard model.startTailscaleRoute(updated) else { return false }
            profile = updated
            persistLiveChange(updated)
        } else {
            model.update(updated)
            profile = updated
            persistLiveChange(updated)
        }
        refreshDNS()
        return true
    }

    private func commitMountPath() {
        guard mountPathText != profile.mountPath else { return }
        var updated = profile
        updated.mountPath = mountPathText
        if !applyRouteConfigurationChange(updated) {
            mountPathText = profile.mountPath
        }
    }

    private func refreshDNS() {
        let token = UUID()
        dnsRefreshToken = token
        let cliPath = profile.tailscalePath
        Task { @MainActor in
            let value = await TailscaleRouteService.dnsNameAsync(cliPath: cliPath) ?? ""
            guard dnsRefreshToken == token else { return }
            dnsName = value
        }
    }
}
