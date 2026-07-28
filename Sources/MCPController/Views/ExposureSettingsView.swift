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

    private let tileColumns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        VStack(spacing: 18) {
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

                LazyVGrid(columns: tileColumns, alignment: .leading, spacing: 12) {
                    infoTile(
                        "Visibility",
                        profile.tailscaleRouteEnabled ? profile.exposureMode.title : "Off",
                        profile.tailscaleRouteEnabled ? "HTTPS \(profile.publicPort)" : "Local only",
                        profile.tailscaleRouteEnabled ? .blue : .secondary,
                        profile.tailscaleRouteEnabled ? "globe" : "network.slash"
                    )
                    infoTile(
                        "Public route",
                        profile.tailscaleRouteEnabled ? profile.normalizedMountPath : "Not configured",
                        profile.tailscaleRouteEnabled ? "Tailscale path" : "Created when remote access is enabled",
                        .secondary,
                        "point.3.connected.trianglepath.dotted"
                    )
                    infoTile(
                        "Public URL",
                        publicAddress ?? "Address unavailable",
                        publicAddress == nil ? "Connect Tailscale to reveal the remote URL" : "Copy and paste into your MCP client",
                        publicAddress == nil ? .secondary : .primary,
                        publicAddress == nil ? "link.badge.plus" : "link",
                        monospaced: true
                    )
                    infoTile(
                        "Authentication",
                        profile.exclusiveGatewayEnabled ? "Bearer access key" : "Direct server access",
                        profile.exclusiveGatewayEnabled ? "Controller-issued key required" : "No controller-issued key",
                        profile.exclusiveGatewayEnabled ? .green : .secondary,
                        profile.exclusiveGatewayEnabled ? "lock.fill" : "lock.open"
                    )
                }
            }
        }
    }

    private var remoteCompatibilityCard: some View {
        ContentCard(title: "Remote client compatibility", symbol: "bolt.horizontal.circle") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
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

                LazyVGrid(columns: tileColumns, alignment: .leading, spacing: 12) {
                    infoTile(
                        "State",
                        compatibilityStatus.title,
                        profile.remoteClientCompatibilityEnabled ? "Per-server compatibility mode" : "Disabled for this server",
                        compatibilityStatus.color,
                        compatibilityStatus.symbol
                    )
                    infoTile(
                        "Remote route",
                        profile.remoteClientCompatibilityEnabled
                            ? (profile.tailscaleRouteEnabled ? profile.exposureMode.title : "Needs Tailscale exposure")
                            : "Not configured",
                        profile.remoteClientCompatibilityEnabled
                            ? "A unique route is kept for remote clients"
                            : "Enabled automatically when this mode turns on",
                        profile.remoteClientCompatibilityEnabled && profile.tailscaleRouteEnabled ? .blue : .secondary,
                        "point.3.filled.connected.trianglepath.dotted"
                    )
                    infoTile(
                        "Session handling",
                        profile.exclusiveGatewayEnabled ? "Controller-managed access keys" : "Direct server transport",
                        profile.remoteClientCompatibilityEnabled ? "Primary AI key is created automatically when needed" : "No compatibility-specific session behavior",
                        profile.exclusiveGatewayEnabled ? .green : .secondary,
                        profile.exclusiveGatewayEnabled ? "person.badge.key.fill" : "bolt.horizontal"
                    )
                    infoTile(
                        "Suggested URL",
                        profile.remoteClientCompatibilityEnabled ? (publicAddress ?? "Available when Tailscale is connected") : "Turn on compatibility mode",
                        profile.remoteClientCompatibilityEnabled ? "Use this for remote MCP clients" : "A public URL appears after setup",
                        profile.remoteClientCompatibilityEnabled && publicAddress != nil ? .primary : .secondary,
                        "rectangle.and_arrow_up_right_and_arrow_down_left",
                        monospaced: true
                    )
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
                        infoTile(
                            "MCP server port",
                            String(profile.localPort),
                            phase.isActive ? "Stop this server to change its local endpoint." : "Unprivileged local port used by the MCP process.",
                            profile.localPort < 1024 ? .red : .secondary,
                            profile.localPort < 1024 ? "exclamationmark.triangle.fill" : "network",
                            monospaced: true
                        )

                        if !phase.isActive {
                            LabeledContent("Edit port") {
                                TextField("4101", text: integerBinding(\.localPort))
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 120)
                            }
                        }

                        if profile.localPort < 1024 {
                            Label("Use port 1024 or higher. For macOS-MCP, restore this to 4101.", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(.top, 12)
                }

                DisclosureGroup("Startup behavior", isExpanded: $showStartupBehavior) {
                    VStack(alignment: .leading, spacing: 12) {
                        LazyVGrid(columns: tileColumns, alignment: .leading, spacing: 12) {
                            infoTile(
                                "Readiness timeout",
                                "\(max(15, Int(profile.startupDelaySeconds)))s",
                                "How long MCP Controller waits for this server to open its port.",
                                .secondary,
                                "timer",
                                monospaced: true
                            )
                            infoTile(
                                "Launch at startup",
                                profile.autoStart ? "Enabled" : "Disabled",
                                profile.autoStart ? "This server starts when MCP Controller opens." : "This server stays stopped until you start it.",
                                profile.autoStart ? .green : .secondary,
                                profile.autoStart ? "play.circle.fill" : "pause.circle"
                            )
                        }

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

    private func infoTile(
        _ title: String,
        _ value: String,
        _ detail: String,
        _ color: Color,
        _ symbol: String,
        monospaced: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(monospaced ? .system(.headline, design: .monospaced).weight(.semibold) : .headline.weight(.semibold))
                .foregroundStyle(color)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, minHeight: 102, alignment: .topLeading)
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
