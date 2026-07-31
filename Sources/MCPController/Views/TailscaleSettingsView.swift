import SwiftUI
import AppKit

struct TailscaleSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dnsName = ""
    @State private var dnsRefreshToken = UUID()
    @State private var mountPathDrafts: [UUID: String] = [:]
    @FocusState private var focusedRouteID: UUID?

    private var serverIndices: [Int] {
        model.profiles.indices.filter { model.profiles[$0].isServer }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                globalControl
                ForEach(serverIndices, id: \.self) { index in
                    routeRow(profile: $model.profiles[index])
                }
            }
            .padding(22)
        }
        .onAppear {
            for profile in model.serverProfiles {
                mountPathDrafts[profile.id] = profile.mountPath
            }
            refreshDNS()
        }
        .onChange(of: focusedRouteID) { previous, current in
            if let previous, previous != current {
                commitMountPath(profileID: previous)
            }
        }
        .animation(AppMotion.standard(reduceMotion: reduceMotion), value: model.tailscaleFunnelRunning)
    }

    private var globalControl: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Label("Shared Funnel", systemImage: "globe").font(.headline)
                    Text(model.tailscaleFunnelRunning ? "Public routes are currently available." : "Public routes stay configured, but the shared Funnel is stopped.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(model.tailscaleFunnelRunning ? "Stop Funnel" : "Start Funnel", systemImage: model.tailscaleFunnelRunning ? "stop.fill" : "play.fill") {
                    if model.tailscaleFunnelRunning { model.stopTailscaleFunnel() } else { model.startTailscaleFunnel() }
                    refreshDNS()
                }
                .buttonStyle(.borderedProminent)
                .tint(model.tailscaleFunnelRunning ? .red : .blue)
            }
            HStack {
                Label(dnsName.isEmpty ? "Tailscale device name unavailable" : dnsName, systemImage: dnsName.isEmpty ? "exclamationmark.triangle" : "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(dnsName.isEmpty ? .orange : .green)
                Spacer()
                Button("Use Default CLI for All") {
                    model.applyDefaultTailscaleCLIToAllProfiles()
                    refreshDNS()
                }
                .controlSize(.small)
            }
        }
        .padding(16).background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 16))
    }

    private func routeRow(profile: Binding<ServerProfile>) -> some View {
        let value = profile.wrappedValue
        let isLiveFunnelRouteLocked = model.tailscaleFunnelRunning && value.exposureMode == .funnel
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(value.name).fontWeight(.medium)
                    Text(value.tailscaleRouteEnabled ? publicAddress(for: value) : "Remote access off")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Toggle("Remote access", isOn: Binding(
                    get: { profile.wrappedValue.tailscaleRouteEnabled },
                    set: { enabled in configure(profile: profile, enabled: enabled) }
                )).toggleStyle(.switch)
            }

            if profile.wrappedValue.tailscaleRouteEnabled {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
                    GridRow {
                        Text("Audience").foregroundStyle(.secondary)
                        Picker("Audience", selection: audienceBinding(for: profile)) {
                            Text("Tailnet only").tag(ExposureMode.tailnet)
                            Text("Public Funnel").tag(ExposureMode.funnel)
                        }.labelsHidden().pickerStyle(.segmented)
                    }
                    GridRow {
                        Text("HTTPS port").foregroundStyle(.secondary)
                        Picker("HTTPS port", selection: httpsPortBinding(for: profile)) {
                            ForEach([443, 8443, 10000], id: \.self) { Text(String($0)).tag($0) }
                        }.labelsHidden().frame(width: 120)
                    }
                    GridRow {
                        Text("Route path").foregroundStyle(.secondary)
                        TextField("/mcp/server", text: mountPathDraftBinding(for: profile))
                            .textFieldStyle(.roundedBorder)
                            .focused($focusedRouteID, equals: value.id)
                            .onSubmit {
                                commitMountPath(profileID: value.id)
                                focusedRouteID = nil
                            }
                    }
                }
                .disabled(isLiveFunnelRouteLocked)

                HStack {
                    Text(publicAddress(for: profile.wrappedValue)).font(.system(.caption, design: .monospaced)).textSelection(.enabled).lineLimit(1)
                    Spacer()
                    Button("Copy", systemImage: "square.on.square") {
                        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(publicAddress(for: profile.wrappedValue), forType: .string)
                    }.labelStyle(.iconOnly).disabled(model.remoteURL(for: profile.wrappedValue) == nil)
                }
            }
        }
        .padding(14).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
    }

    private func configure(profile: Binding<ServerProfile>, enabled: Bool) {
        var value = profile.wrappedValue
        if enabled {
            value.tailscaleRouteEnabled = true
            if value.exposureMode == .disabled { value.exposureMode = .tailnet }
            if value.normalizedMountPath == "/" { value.mountPath = model.uniqueMountPath(for: value.name) }
            if value.tailscalePath.isEmpty || !TailscaleRouteService.isCLIAvailable(at: value.tailscalePath) {
                value.tailscalePath = TailscaleRouteService.defaultCLIPath
            }
            if model.startTailscaleRoute(value) {
                profile.wrappedValue = value
                mountPathDrafts[value.id] = value.mountPath
            }
        } else {
            if model.stopTailscaleRoute(value) {
                value.tailscaleRouteEnabled = false
                profile.wrappedValue = value
            }
        }
        refreshDNS()
    }

    private func audienceBinding(for profile: Binding<ServerProfile>) -> Binding<ExposureMode> {
        Binding(
            get: { profile.wrappedValue.exposureMode },
            set: { value in
                var updated = profile.wrappedValue
                updated.exposureMode = value
                applyRouteConfigurationChange(updated, to: profile)
            }
        )
    }

    private func httpsPortBinding(for profile: Binding<ServerProfile>) -> Binding<Int> {
        Binding(
            get: { profile.wrappedValue.publicPort },
            set: { value in
                var updated = profile.wrappedValue
                updated.publicPort = value
                applyRouteConfigurationChange(updated, to: profile)
            }
        )
    }

    private func mountPathDraftBinding(for profile: Binding<ServerProfile>) -> Binding<String> {
        let id = profile.wrappedValue.id
        return Binding(
            get: { mountPathDrafts[id] ?? profile.wrappedValue.mountPath },
            set: { mountPathDrafts[id] = $0 }
        )
    }

    private func applyRouteConfigurationChange(_ updated: ServerProfile, to profile: Binding<ServerProfile>) {
        if updated.tailscaleRouteEnabled {
            if model.startTailscaleRoute(updated) {
                profile.wrappedValue = updated
                mountPathDrafts[updated.id] = updated.mountPath
            }
        } else {
            model.update(updated)
            profile.wrappedValue = updated
            mountPathDrafts[updated.id] = updated.mountPath
        }
        refreshDNS()
    }

    private func commitMountPath(profileID: UUID) {
        guard let index = model.profiles.firstIndex(where: { $0.id == profileID && $0.isServer }) else {
            mountPathDrafts.removeValue(forKey: profileID)
            return
        }
        let current = model.profiles[index]
        let draft = mountPathDrafts[profileID] ?? current.mountPath
        guard draft != current.mountPath else { return }

        var updated = current
        updated.mountPath = draft
        if updated.tailscaleRouteEnabled {
            if model.startTailscaleRoute(updated) {
                model.profiles[index] = updated
                mountPathDrafts[profileID] = updated.mountPath
            } else {
                mountPathDrafts[profileID] = current.mountPath
            }
        } else {
            model.update(updated)
            mountPathDrafts[profileID] = updated.mountPath
        }
        refreshDNS()
    }

    private func publicAddress(for profile: ServerProfile) -> String {
        model.remoteURL(for: profile) ?? "Address available when Tailscale is connected"
    }

    private func refreshDNS() {
        let token = UUID()
        dnsRefreshToken = token
        let path = model.serverProfiles.first?.tailscalePath ?? TailscaleRouteService.defaultCLIPath
        Task { @MainActor in
            let value = await TailscaleRouteService.dnsNameAsync(cliPath: path) ?? ""
            guard dnsRefreshToken == token else { return }
            dnsName = value
        }
    }
}
