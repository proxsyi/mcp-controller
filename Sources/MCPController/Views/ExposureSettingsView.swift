import SwiftUI
import AppKit

struct ExposureSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var profile: ServerProfile
    let phase: RuntimePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showLocalEndpoint = false
    @State private var showStartupBehavior = false
    @State private var dnsName = ""

    var body: some View {
        VStack(spacing: 18) {
            summaryStrip
            remoteAccessCard
            remoteCompatibilityCard
            GatewayAccessView(profile: $profile, isRunning: phase.isActive)
            advancedCard
        }
        .animation(AppMotion.standard(reduceMotion: reduceMotion), value: profile.tailscaleRouteEnabled)
        .onAppear { refreshDNS() }
        .onChange(of: profile.tailscalePath) { _, _ in refreshDNS() }
        .onChange(of: profile.tailscaleRouteEnabled) { _, _ in refreshDNS() }
    }

    private var summaryStrip: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Remote summary").font(.headline)
                Spacer()
                if let publicAddress {
                    Button("Copy URL", systemImage: "square.on.square") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(publicAddress, forType: .string)
                    }
                    .controlSize(.small)
                }
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    summaryTile(
                        "Exposure",
                        exposureValue,
                        profile.tailscaleRouteEnabled ? profile.normalizedMountPath : "Local only",
                        exposureColor,
                        exposureSymbol
                    )
                    summaryTile(
                        "Compatibility",
                        compatibilityStatus.title,
                        compatibilityStatus.detail,
                        compatibilityStatus.color,
                        compatibilityStatus.symbol
                    )
                }
                GridRow {
                    summaryTile(
                        "Access",
                        profile.exclusiveGatewayEnabled ? "Exclusive" : "Direct",
                        profile.exclusiveGatewayEnabled ? "Bearer access key required" : "No controller-issued key",
                        profile.exclusiveGatewayEnabled ? .green : .secondary,
                        profile.exclusiveGatewayEnabled ? "lock.fill" : "lock.open"
                    )
                    summaryTile(
                        "Endpoint",
                        publicAddress ?? "Address unavailable",
                        publicAddress == nil ? "Connect Tailscale to reveal the public URL" : "HTTPS \(profile.publicPort)",
                        publicAddress == nil ? .secondary : .blue,
                        publicAddress == nil ? "network.slash" : "link"
                    )
                }
            }
        }
        .padding(18)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 18))
    }

    private var remoteAccessCard: some View {
        ContentCard(title: "Remote access", symbol: "globe") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(profile.tailscaleRouteEnabled ? "Exposed through Tailscale" : "Not exposed yet")
                            .fontWeight(.medium)
                        Text(profile.tailscaleRouteEnabled
                             ? "Use Settings to manage its route, visibility, and Funnel lifecycle."
                             : "Turn on Tailscale in Settings to give this server a remote address.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    SettingsLink { Label("Manage", systemImage: "gearshape") }
                }

                if profile.tailscaleRouteEnabled {
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                        GridRow {
                            Text("Visibility").foregroundStyle(.secondary)
                            Text(profile.exposureMode.title)
                        }
                        GridRow {
                            Text("Public route").foregroundStyle(.secondary)
                            Text(profile.normalizedMountPath)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        }
                        GridRow {
                            Text("Public URL").foregroundStyle(.secondary)
                            Text(publicAddress ?? "Available when Tailscale is connected")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(publicAddress == nil ? .secondary : .primary)
                                .textSelection(.enabled)
                        }
                        GridRow {
                            Text("Authentication").foregroundStyle(.secondary)
                            Text(profile.exclusiveGatewayEnabled ? "Bearer access key" : "Direct server access")
                        }
                    }
                } else {
                    Label("Remote access is off for this server. Configure it in the Tailscale settings page.", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var remoteCompatibilityCard: some View {
        ContentCard(title: "Remote client compatibility", symbol: "bolt.horizontal.circle") {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Compatibility-first remote setup")
                            .fontWeight(.medium)
                        Text("Keeps this server in a remote-friendly configuration for clients like Notion.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("Remote client compatibility", isOn: compatibilityBinding)
                        .labelsHidden()
                        .disabled(phase.isActive)
                }

                statusPill(compatibilityStatus.title, color: compatibilityStatus.color, systemImage: compatibilityStatus.symbol)
                Text(compatibilityStatus.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if profile.remoteClientCompatibilityEnabled {
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                        GridRow {
                            Text("Remote route").foregroundStyle(.secondary)
                            Text(profile.tailscaleRouteEnabled ? profile.exposureMode.title : "Needs Tailscale exposure")
                        }
                        GridRow {
                            Text("Session handling").foregroundStyle(.secondary)
                            Text(profile.exclusiveGatewayEnabled ? "Controller-managed access keys" : "Direct server transport")
                        }
                        GridRow {
                            Text("Suggested URL").foregroundStyle(.secondary)
                            Text(publicAddress ?? "Available when Tailscale is connected")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(publicAddress == nil ? .secondary : .primary)
                                .textSelection(.enabled)
                        }
                    }
                } else {
                    Label("Turning this on will auto-configure Tailscale exposure, a unique route, and controller access keys for this server.", systemImage: "slider.horizontal.3")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if phase.isActive {
                    Text("Stop the server to change compatibility configuration.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var advancedCard: some View {
        ContentCard(title: "Advanced", symbol: "slider.horizontal.3") {
            VStack(alignment: .leading, spacing: 14) {
                DisclosureGroup("Local endpoint", isExpanded: $showLocalEndpoint) {
                    VStack(alignment: .leading, spacing: 12) {
                        LabeledContent("MCP server port") {
                            TextField("4101", text: integerBinding(\.localPort))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 120)
                                .disabled(phase.isActive)
                        }
                        Text("This is the unprivileged local port used by the MCP process. It is separate from public HTTPS port 443.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if profile.localPort < 1024 {
                            Label("Use port 1024 or higher. For macOS-MCP, restore this to 4101.", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.red)
                        } else if phase.isActive {
                            Label("Stop this server to change its MCP port.", systemImage: "info.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 12)
                }

                DisclosureGroup("Startup behavior", isExpanded: $showStartupBehavior) {
                    VStack(alignment: .leading, spacing: 14) {
                        LabeledContent("Readiness timeout") {
                            HStack {
                                Slider(value: $profile.startupDelaySeconds, in: 0...30, step: 0.5)
                                    .frame(width: 220)
                                Text("\(max(15, Int(profile.startupDelaySeconds)))s")
                                    .monospacedDigit()
                                    .frame(width: 42, alignment: .trailing)
                            }
                        }
                        Toggle("Start when MCP Controller opens", isOn: $profile.autoStart)
                    }
                    .padding(.top, 12)
                }
            }
        }
    }

    private var exposureValue: String {
        guard profile.tailscaleRouteEnabled else { return "Not exposed" }
        return profile.exposureMode == .funnel ? "Public Funnel" : profile.exposureMode.title
    }

    private var exposureColor: Color {
        guard profile.tailscaleRouteEnabled else { return .secondary }
        return profile.exposureMode == .funnel ? .blue : .green
    }

    private var exposureSymbol: String {
        guard profile.tailscaleRouteEnabled else { return "network.slash" }
        return profile.exposureMode == .funnel ? "globe" : "lock.shield"
    }

    private var publicAddress: String? {
        guard profile.tailscaleRouteEnabled, profile.exposureMode != .disabled, !dnsName.isEmpty else { return nil }
        return TailscaleRouteService.address(for: profile, dnsName: dnsName)
    }

    private var compatibilityStatus: (title: String, detail: String, color: Color, symbol: String) {
        if !profile.remoteClientCompatibilityEnabled {
            return ("Off", "Turn this on to keep the server in a compatibility-first remote configuration.", .secondary, "power")
        }
        if !profile.tailscaleRouteEnabled || profile.exposureMode == .disabled {
            return ("Needs Tailscale", "Enable Tailscale exposure to make this server reachable by remote clients.", .orange, "exclamationmark.triangle.fill")
        }
        if phase.isFailed {
            return ("Needs attention", "Resolve the server startup failure before connecting a remote client.", .red, "xmark.octagon.fill")
        }
        if dnsName.isEmpty {
            return ("Waiting for Tailscale", "Connect Tailscale on this Mac to reveal the public URL and remote route.", .orange, "globe.badge.chevron.backward")
        }
        if phase.isActive {
            return ("Configured", "Remote exposure, a unique route, and controller access keys are configured for this server.", .green, "checkmark.shield.fill")
        }
        return ("Ready when running", "Start the server to expose its compatibility-focused remote route.", .secondary, "pause.circle")
    }

    private var compatibilityBinding: Binding<Bool> {
        Binding(
            get: { profile.remoteClientCompatibilityEnabled },
            set: { enabled in
                profile.remoteClientCompatibilityEnabled = enabled
                guard enabled else {
                    refreshDNS()
                    return
                }
                profile.exclusiveGatewayEnabled = true
                if profile.clientCredentials.isEmpty {
                    profile.clientCredentials.append(.generate(name: "Primary AI"))
                }
                profile.tailscaleRouteEnabled = true
                if profile.exposureMode == .disabled {
                    profile.exposureMode = .funnel
                }
                if profile.normalizedMountPath == "/" {
                    profile.mountPath = model.uniqueMountPath(for: profile.name)
                }
                if profile.gatewayPort == profile.localPort {
                    profile.gatewayPort = model.nextAvailableGatewayPort(startingAt: profile.gatewayPort + 1)
                }
                refreshDNS()
            }
        )
    }

    private func summaryTile(_ title: String, _ value: String, _ detail: String, _ color: Color, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.weight(.semibold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
    }

    private func statusPill(_ title: String, color: Color, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.14), in: Capsule())
            .foregroundStyle(color)
    }

    private func refreshDNS() {
        dnsName = TailscaleRouteService.dnsName(cliPath: profile.tailscalePath) ?? ""
    }

    private func integerBinding(_ keyPath: WritableKeyPath<ServerProfile, Int>) -> Binding<String> {
        Binding(get: { String(profile[keyPath: keyPath]) }, set: { text in
            let digits = text.filter(\.isNumber)
            if let value = Int(digits), (1...65535).contains(value) { profile[keyPath: keyPath] = value }
        })
    }
}
