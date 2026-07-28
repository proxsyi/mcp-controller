import SwiftUI

struct ExposureSettingsView: View {
    @Binding var profile: ServerProfile
    let phase: RuntimePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var advancedBehavior = false

    var body: some View {
        VStack(spacing: 18) {
            ContentCard(title: "Local connection", symbol: "network") {
                VStack(alignment: .leading, spacing: 12) {
                    LabeledContent("MCP server port") {
                        TextField("4101", text: integerBinding(\.localPort))
                            .textFieldStyle(.roundedBorder).frame(width: 120).disabled(phase.isActive)
                    }
                    Text("This is the unprivileged local port used by the MCP process. It is separate from public HTTPS port 443.")
                        .font(.caption).foregroundStyle(.secondary)
                    if profile.localPort < 1024 {
                        Label("Use port 1024 or higher. For macOS-MCP, restore this to 4101.", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.weight(.medium)).foregroundStyle(.red)
                    } else if phase.isActive {
                        Label("Stop this server to change its MCP port.", systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            ContentCard(title: "Tailscale", symbol: "globe") {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(profile.tailscaleRouteEnabled ? "Included in Tailscale" : "Not configured for Tailscale").fontWeight(.medium)
                        if profile.tailscaleRouteEnabled {
                            Text("\(profile.exposureMode.title) · HTTPS \(profile.publicPort) · \(profile.normalizedMountPath)")
                                .font(.caption).foregroundStyle(.secondary)
                            Text("Starting this MCP server automatically starts the configured Funnel routes.")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("Configure its visibility, address, and Funnel lifecycle from Settings.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    SettingsLink { Label("Manage", systemImage: "gearshape") }
                }
            }

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
        .animation(AppMotion.standard(reduceMotion: reduceMotion), value: profile.tailscaleRouteEnabled)
    }

    private func integerBinding(_ keyPath: WritableKeyPath<ServerProfile, Int>) -> Binding<String> {
        Binding(get: { String(profile[keyPath: keyPath]) }, set: { text in
            let digits = text.filter(\.isNumber)
            if let value = Int(digits), (1...65535).contains(value) { profile[keyPath: keyPath] = value }
        })
    }
}
