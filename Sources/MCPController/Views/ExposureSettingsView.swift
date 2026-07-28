import SwiftUI

struct ExposureSettingsView: View {
    @Binding var profile: ServerProfile
    let phase: RuntimePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var advancedBehavior = false

    var body: some View {
        VStack(spacing: 18) {
            ContentCard(title: "Connection", symbol: "point.3.connected.trianglepath.dotted") {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("Who can connect?", selection: $profile.exposureMode) {
                        ForEach(ExposureMode.allCases) { mode in Text(mode.title).tag(mode) }
                    }
                    .pickerStyle(.segmented)
                    .disabled(phase.isActive)

                    Label(exposureExplanation, systemImage: exposureSymbol)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .contentTransition(.interpolate)

                    Divider()

                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
                        GridRow {
                            Text("MCP server port").foregroundStyle(.secondary)
                            TextField("4101", text: integerBinding(\.localPort))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 120)
                                .disabled(phase.isActive)
                        }

                        if profile.exposureMode != .disabled {
                            GridRow {
                                Text("Public HTTPS port").foregroundStyle(.secondary)
                                Picker("Public HTTPS port", selection: $profile.publicPort) {
                                    ForEach([443, 8443, 10000], id: \.self) { Text(String($0)).tag($0) }
                                }
                                .labelsHidden()
                                .frame(width: 120)
                                .disabled(phase.isActive)
                            }
                            GridRow {
                                Text("Mount path").foregroundStyle(.secondary)
                                TextField("/mcp/server", text: $profile.mountPath)
                                    .textFieldStyle(.roundedBorder)
                                    .disabled(phase.isActive)
                            }
                            GridRow {
                                Text("Tailscale CLI").foregroundStyle(.secondary)
                                TextField("/usr/local/bin/tailscale", text: $profile.tailscalePath)
                                    .textFieldStyle(.roundedBorder)
                                    .disabled(phase.isActive)
                            }
                        }
                    }

                    if phase.isActive {
                        Label("Stop this server to edit connection settings.", systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else if profile.exposureMode != .disabled {
                        endpointPreview
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }

            GatewayAccessView(profile: $profile, isRunning: phase.isActive)

            ContentCard(title: "Behavior", symbol: "timer") {
                DisclosureGroup("Startup options", isExpanded: $advancedBehavior) {
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
        .animation(AppMotion.standard(reduceMotion: reduceMotion), value: profile.exposureMode)
        .animation(AppMotion.standard(reduceMotion: reduceMotion), value: profile.exclusiveGatewayEnabled)
    }

    private var endpointPreview: some View {
        HStack(spacing: 8) {
            Image(systemName: "link")
            Text("HTTPS :\(profile.publicPort)\(profile.normalizedMountPath)")
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
            Spacer()
            Text(profile.exposureMode == .funnel ? "Public" : "Tailnet only")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.12), in: Capsule())
        }
        .padding(10)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private var exposureExplanation: String {
        switch profile.exposureMode {
        case .disabled: "Only apps on this Mac can reach the selected endpoint."
        case .tailnet: "Only devices signed into your Tailscale network can connect."
        case .funnel: "Creates a public HTTPS route through Tailscale Funnel."
        }
    }

    private var exposureSymbol: String {
        switch profile.exposureMode {
        case .disabled: "laptopcomputer"
        case .tailnet: "point.3.connected.trianglepath.dotted"
        case .funnel: "globe"
        }
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
