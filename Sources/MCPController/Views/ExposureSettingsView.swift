import SwiftUI
import AppKit

struct ExposureSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var profile: ServerProfile
    let phase: RuntimePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dnsName = ""

    var body: some View {
        VStack(spacing: 16) {
            remoteAccessCard
            remoteCompatibilityCard
            GatewayAccessView(profile: $profile, isRunning: phase.isActive)
            advancedCard
        }
        .animation(AppMotion.standard(reduceMotion: reduceMotion), value: profile.tailscaleRouteEnabled)
        .onAppear { refreshDNS() }
        .onChange(of: profile.tailscalePath) { _, _ in refreshDNS() }
        .onChange(of: profile.tailscaleRouteEnabled) { _, _ in refreshDNS() }
        .onChange(of: profile.exposureMode) { _, _ in refreshDNS() }
    }

    private var remoteAccessCard: some View {
        ContentCard(title: "Remote access", symbol: "globe") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Remote route")
                            .fontWeight(.medium)
                        Text(profile.tailscaleRouteEnabled
                             ? "These controls update this server’s Tailscale route directly."
                             : "Turn this on to give this server a Tailscale route.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("Remote access", isOn: remoteAccessBinding)
                        .labelsHidden()
                }

                if profile.tailscaleRouteEnabled {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                        GridRow {
                            Text("Audience").foregroundStyle(.secondary)
                            Picker("Audience", selection: $profile.exposureMode) {
                                Text("Tailnet only").tag(ExposureMode.tailnet)
                                Text("Public Funnel").tag(ExposureMode.funnel)
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                        }
                        GridRow {
                            Text("HTTPS port").foregroundStyle(.secondary)
                            Picker("HTTPS port", selection: $profile.publicPort) {
                                ForEach([443, 8443, 10000], id: \.self) { Text(String($0)).tag($0) }
                            }
                            .labelsHidden()
                            .frame(width: 120)
                        }
                        GridRow {
                            Text("Route path").foregroundStyle(.secondary)
                            TextField("/mcp/server", text: $profile.mountPath)
                                .textFieldStyle(.roundedBorder)
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
                    .disabled(model.tailscaleFunnelRunning)

                    Text(model.tailscaleFunnelRunning
                         ? "Stop the shared Funnel in Settings before editing a live public route."
                         : "These settings will be used the next time the shared Funnel starts.")
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
                        Text("Compatibility mode")
                            .fontWeight(.medium)
                        Text("Keeps remote access, route protection, and the default client key aligned for this server.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("Remote client compatibility", isOn: compatibilityBinding)
                        .labelsHidden()
                        .disabled(phase.isActive)
                }

                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                    GridRow {
                        Text("Status").foregroundStyle(.secondary)
                        statusLine
                    }
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

    private var advancedCard: some View {
        ContentCard(title: "Advanced", symbol: "slider.horizontal.3") {
            VStack(alignment: .leading, spacing: 12) {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                    GridRow {
                        Text("Local port").foregroundStyle(.secondary)
                        TextField("4101", text: integerBinding(\.localPort))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                            .disabled(phase.isActive)
                    }
                    GridRow {
                        Text("Readiness timeout").foregroundStyle(.secondary)
                        HStack(spacing: 10) {
                            Slider(value: $profile.startupDelaySeconds, in: 0...30, step: 0.5)
                                .frame(width: 220)
                            Text("\(max(15, Int(profile.startupDelaySeconds)))s")
                                .monospacedDigit()
                                .frame(width: 40, alignment: .trailing)
                        }
                    }
                    GridRow {
                        Text("Start at launch").foregroundStyle(.secondary)
                        Toggle("Start when MCP Controller opens", isOn: $profile.autoStart)
                            .labelsHidden()
                    }
                }

                if profile.localPort < 1024 {
                    Label("Use port 1024 or higher.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.red)
                } else if phase.isActive {
                    Text("Stop the server before changing its local port.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var publicAddress: String? {
        guard profile.tailscaleRouteEnabled, profile.exposureMode != .disabled, !dnsName.isEmpty else { return nil }
        return TailscaleRouteService.address(for: profile, dnsName: dnsName)
    }

    private var audienceLabel: String {
        switch profile.exposureMode {
        case .disabled: return "Off"
        case .tailnet: return "Tailnet only"
        case .funnel: return "Public Funnel"
        }
    }

    private var defaultKeyLabel: String {
        if let credential = profile.clientCredentials.first(where: { $0.name == "Primary AI" }) {
            return credential.name
        }
        return profile.clientCredentials.first?.name ?? "Will create Primary AI"
    }

    private var statusLine: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(compatibilityColor)
                .frame(width: 8, height: 8)
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
        if !profile.tailscaleRouteEnabled || profile.exposureMode == .disabled || dnsName.isEmpty { return .orange }
        if phase.isFailed { return .red }
        return phase.isActive ? .green : .secondary
    }

    private var remoteAccessBinding: Binding<Bool> {
        Binding(
            get: { profile.tailscaleRouteEnabled },
            set: { enabled in
                applyRemoteAccess(enabled: enabled)
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
                    if updated.clientCredentials.isEmpty {
                        updated.clientCredentials.append(.generate(name: "Primary AI"))
                    }
                    if updated.gatewayPort == updated.localPort {
                        updated.gatewayPort = model.nextAvailableGatewayPort(startingAt: updated.gatewayPort + 1)
                    }
                    if updated.exposureMode == .disabled {
                        updated.exposureMode = .funnel
                    }
                    if updated.normalizedMountPath == "/" {
                        updated.mountPath = model.uniqueMountPath(for: updated.name)
                    }
                    profile = updated
                    if !updated.tailscaleRouteEnabled {
                        applyRemoteAccess(enabled: true)
                    }
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
            if updated.exposureMode == .disabled {
                updated.exposureMode = .funnel
            }
            if updated.normalizedMountPath == "/" {
                updated.mountPath = model.uniqueMountPath(for: updated.name)
            }
            updated.tailscalePath = TailscaleRouteService.defaultCLIPath
            if model.tailscaleFunnelRunning {
                if model.startTailscaleRoute(updated) {
                    profile = updated
                }
            } else {
                model.update(updated)
                profile = updated
            }
        } else {
            let current = profile
            var updated = profile
            updated.tailscaleRouteEnabled = false
            if model.tailscaleFunnelRunning {
                if model.stopTailscaleRoute(current) {
                    profile = updated
                }
            } else {
                model.update(updated)
                profile = updated
            }
        }
        refreshDNS()
    }

    private func refreshDNS() {
        dnsName = TailscaleRouteService.dnsName(cliPath: profile.tailscalePath) ?? ""
    }

    private func integerBinding(_ keyPath: WritableKeyPath<ServerProfile, Int>) -> Binding<String> {
        Binding(
            get: { String(profile[keyPath: keyPath]) },
            set: { text in
                let digits = text.filter(\.isNumber)
                if let value = Int(digits), (1...65535).contains(value) {
                    profile[keyPath: keyPath] = value
                }
            }
        )
    }
}
