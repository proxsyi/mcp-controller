import SwiftUI
import AppKit

struct ExposureSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var profile: ServerProfile
    let phase: RuntimePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var advancedBehavior = false
    @State private var showTailscaleCLI = false
    @State private var dnsName = ""

    private var cliAvailable: Bool { TailscaleRouteService.isCLIAvailable(at: profile.tailscalePath) }

    var body: some View {
        VStack(spacing: 18) {
            ContentCard(title: "Connection", symbol: "point.3.connected.trianglepath.dotted") {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("Who can connect?", selection: $profile.exposureMode) {
                        ForEach(ExposureMode.allCases) { mode in Text(mode.title).tag(mode) }
                    }
                    .pickerStyle(.segmented)
                    .disabled(profile.tailscaleRouteEnabled)

                    Label(exposureExplanation, systemImage: exposureSymbol)
                        .font(.caption).foregroundStyle(.secondary).contentTransition(.interpolate)

                    Divider()

                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
                        GridRow {
                            Text("MCP server port").foregroundStyle(.secondary)
                            TextField("4101", text: integerBinding(\.localPort))
                                .textFieldStyle(.roundedBorder).frame(width: 120).disabled(phase.isActive)
                        }
                        if profile.exposureMode != .disabled {
                            GridRow {
                                Text("Public HTTPS port").foregroundStyle(.secondary)
                                Picker("Public HTTPS port", selection: $profile.publicPort) {
                                    ForEach([443, 8443, 10000], id: \.self) { Text(String($0)).tag($0) }
                                }
                                .labelsHidden().frame(width: 120).disabled(profile.tailscaleRouteEnabled)
                            }
                            GridRow {
                                Text("Address path").foregroundStyle(.secondary)
                                TextField("/mcp/server", text: $profile.mountPath)
                                    .textFieldStyle(.roundedBorder).disabled(profile.tailscaleRouteEnabled)
                            }
                        }
                    }

                    if phase.isActive {
                        Label("Stop this server to change its MCP port.", systemImage: "info.circle")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    if profile.exposureMode != .disabled {
                        DisclosureGroup("Tailscale CLI", isExpanded: $showTailscaleCLI) {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    TextField(TailscaleRouteService.defaultCLIPath, text: $profile.tailscalePath)
                                        .textFieldStyle(.roundedBorder).disabled(profile.tailscaleRouteEnabled)
                                    Button("Use Default") {
                                        profile.tailscalePath = TailscaleRouteService.defaultCLIPath
                                        refreshDNSName()
                                    }
                                    .disabled(profile.tailscaleRouteEnabled)
                                }
                                Label(cliAvailable ? "Tailscale CLI found" : "Tailscale CLI not found", systemImage: cliAvailable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .font(.caption).foregroundStyle(cliAvailable ? .green : .orange)
                            }.padding(.top, 10)
                        }
                    }
                }
            }

            if profile.exposureMode != .disabled { routeControl }
            GatewayAccessView(profile: $profile, isRunning: phase.isActive)

            ContentCard(title: "Behavior", symbol: "timer") {
                DisclosureGroup("Startup options", isExpanded: $advancedBehavior) {
                    VStack(alignment: .leading, spacing: 14) {
                        LabeledContent("Readiness timeout") {
                            HStack {
                                Slider(value: $profile.startupDelaySeconds, in: 0...30, step: 0.5).frame(width: 220)
                                Text("\(max(15, Int(profile.startupDelaySeconds)))s").monospacedDigit().frame(width: 42, alignment: .trailing)
                            }
                        }
                        Toggle("Start when MCP Controller opens", isOn: $profile.autoStart)
                    }.padding(.top, 12)
                }
            }
        }
        .onAppear {
            if !cliAvailable { profile.tailscalePath = TailscaleRouteService.defaultCLIPath }
            refreshDNSName()
        }
        .onChange(of: profile.tailscalePath) { _, _ in refreshDNSName() }
        .animation(AppMotion.standard(reduceMotion: reduceMotion), value: profile.exposureMode)
        .animation(AppMotion.standard(reduceMotion: reduceMotion), value: profile.tailscaleRouteEnabled)
    }

    private var routeControl: some View {
        ContentCard(title: profile.exposureMode == .funnel ? "Tailscale Funnel" : "Tailscale Serve", symbol: profile.exposureMode == .funnel ? "globe" : "point.3.connected.trianglepath.dotted") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(profile.tailscaleRouteEnabled ? "Route is enabled" : "Route is off").fontWeight(.medium)
                        Text(profile.tailscaleRouteEnabled ? "This server is published at the address below." : "Start the route when you are ready to publish this server.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(profile.tailscaleRouteEnabled ? "Stop Route" : "Start Route", systemImage: profile.tailscaleRouteEnabled ? "stop.fill" : "play.fill") {
                        if profile.tailscaleRouteEnabled {
                            if model.stopTailscaleRoute(profile) { profile.tailscaleRouteEnabled = false }
                        } else if model.startTailscaleRoute(profile) {
                            profile.tailscaleRouteEnabled = true; refreshDNSName()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(profile.tailscaleRouteEnabled ? .red : .blue)
                    .disabled(!phase.isActive || !cliAvailable)
                }

                HStack(spacing: 8) {
                    Image(systemName: dnsName.isEmpty ? "link.badge.plus" : "link")
                    Text(publicAddress).font(.system(.caption, design: .monospaced)).textSelection(.enabled).lineLimit(1)
                    Spacer()
                    Button("Refresh address", systemImage: "arrow.clockwise") { refreshDNSName() }
                        .labelStyle(.iconOnly).help("Refresh Tailscale address")
                    Button("Copy address", systemImage: "square.on.square") {
                        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(publicAddress, forType: .string)
                    }.labelStyle(.iconOnly).help("Copy route address").disabled(dnsName.isEmpty)
                }
                .padding(10).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 11))

                if !phase.isActive {
                    Label("Start the MCP server before starting its route.", systemImage: "info.circle").font(.caption).foregroundStyle(.orange)
                } else if !cliAvailable {
                    Label("Choose a valid Tailscale CLI before starting the route.", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                }
            }
        }
    }

    private var publicAddress: String {
        dnsName.isEmpty ? "Tailscale address unavailable" : TailscaleRouteService.address(for: profile, dnsName: dnsName)
    }
    private func refreshDNSName() { dnsName = TailscaleRouteService.dnsName(cliPath: profile.tailscalePath) ?? "" }
    private var exposureExplanation: String {
        switch profile.exposureMode {
        case .disabled: "Only apps on this Mac can reach the selected endpoint."
        case .tailnet: "Configure a private address available only inside your tailnet."
        case .funnel: "Configure a public HTTPS address through Tailscale Funnel."
        }
    }
    private var exposureSymbol: String {
        switch profile.exposureMode { case .disabled: "laptopcomputer"; case .tailnet: "point.3.connected.trianglepath.dotted"; case .funnel: "globe" }
    }
    private func integerBinding(_ keyPath: WritableKeyPath<ServerProfile, Int>) -> Binding<String> {
        Binding(get: { String(profile[keyPath: keyPath]) }, set: { text in
            let digits = text.filter(\.isNumber)
            if let value = Int(digits), (1...65535).contains(value) { profile[keyPath: keyPath] = value }
        })
    }
}
