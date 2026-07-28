import SwiftUI
import AppKit

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingAddServer = false
    @State private var searchText = ""

    private var filteredProfiles: [ServerProfile] {
        guard !searchText.isEmpty else { return model.profiles }
        return model.profiles.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.description.localizedCaseInsensitiveContains(searchText) ||
            $0.exposureMode.title.localizedCaseInsensitiveContains(searchText) ||
            model.phase(for: $0.id).title.localizedCaseInsensitiveContains(searchText) ||
            ($0.tailscaleRouteEnabled && "tailscale routed public".localizedCaseInsensitiveContains(searchText))
        }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $model.selectedID) {
                Section {
                    ForEach(filteredProfiles) { profile in
                        ServerRow(profile: profile)
                            .tag(profile.id)
                            .contextMenu { contextMenu(for: profile) }
                    }
                } header: { sidebarSummary }
            }
            .navigationTitle("MCP Servers")
            .searchable(text: $searchText, placement: .sidebar, prompt: "Find a server")
            .overlay {
                if model.profiles.isEmpty {
                    ContentUnavailableView {
                        Label("No servers yet", systemImage: "server.rack")
                    } description: {
                        Text("Add an MCP server, then start it when you need it.")
                    } actions: {
                        Button("Add Server", systemImage: "plus") { showingAddServer = true }.buttonStyle(.borderedProminent)
                    }
                } else if filteredProfiles.isEmpty { ContentUnavailableView.search(text: searchText) }
            }
        } detail: {
            ZStack {
                Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
                if let id = model.selectedID, let profile = model.profiles.first(where: { $0.id == id }) {
                    ServerDetailView(profile: profile).id(profile.id).transition(.opacity.combined(with: .move(edge: .trailing)))
                } else {
                    ContentUnavailableView("Select a server", systemImage: "slider.horizontal.3", description: Text("Choose a server to configure or control it."))
                }
            }
            .animation(AppMotion.standard(reduceMotion: reduceMotion), value: model.selectedID)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Add server", systemImage: "plus") { showingAddServer = true }.help("Add an MCP server")
                SettingsLink { Label("Settings", systemImage: "gearshape") }.help("Settings (⌘,)")
            }
        }
        .sheet(isPresented: $showingAddServer) { AddServerView().environmentObject(model) }
        .alert("MCP Controller", isPresented: Binding(get: { model.presentedError != nil }, set: { if !$0 { model.presentedError = nil } })) {
            Button("OK") { model.presentedError = nil }
        } message: { Text(model.presentedError ?? "") }
    }

    @ViewBuilder
    private func contextMenu(for profile: ServerProfile) -> some View {
        let phase = model.phase(for: profile.id)
        if phase.isActive {
            Button("Stop", systemImage: "stop.fill") { model.stop(profile) }
        } else {
            Button("Start", systemImage: "play.fill") { model.start(profile) }
        }
        Button("Copy Logs", systemImage: "square.on.square") { copyLogs(for: profile, resetFailure: phase.isFailed) }
            .disabled(model.logs[profile.id, default: ""].isEmpty)
        Divider()
        Button("Duplicate", systemImage: "plus.square.on.square") { model.duplicate(profile) }
        Button("Remove", systemImage: "trash", role: .destructive) { model.remove(profile) }
    }

    private var sidebarSummary: some View {
        HStack(spacing: 8) {
            Text("\(model.profiles.count) configured")
            Spacer(minLength: 12)
            if model.failedCount > 0 {
                Label("\(model.failedCount)", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red).fixedSize()
            }
            if model.runningCount > 0 {
                Label("\(model.runningCount)", systemImage: "bolt.fill")
                    .foregroundStyle(.green).contentTransition(.numericText()).fixedSize()
            }
        }
        .textCase(nil).font(.caption.weight(.medium)).foregroundStyle(.secondary).padding(.vertical, 4).padding(.trailing, 12)
    }

    private func copyLogs(for profile: ServerProfile, resetFailure: Bool) {
        let text = resetFailure ? model.acknowledgeFailureAndReturnLogs(for: profile.id) : model.logs[profile.id, default: ""]
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
    }
}

private struct ServerRow: View {
    @EnvironmentObject private var model: AppModel
    let profile: ServerProfile
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    private var phase: RuntimePhase { model.phase(for: profile.id) }

    var body: some View {
        HStack(spacing: 11) {
            ZStack {
                Circle().fill(statusColor.opacity(0.16)).frame(width: 30, height: 30)
                Image(systemName: profile.tailscaleRouteEnabled ? "globe" : "server.rack")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(statusColor)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(profile.name).fontWeight(.medium).lineLimit(1)
                HStack(spacing: 4) {
                    Text(subtitle).lineLimit(1)
                    if profile.tailscaleRouteEnabled { Image(systemName: "link").accessibilityLabel("Tailscale route enabled") }
                }.font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            actionControl
        }
        .padding(.vertical, 5).contentShape(Rectangle()).scaleEffect(hovering && !reduceMotion ? 1.012 : 1)
        .onHover { value in withAnimation(AppMotion.quick(reduceMotion: reduceMotion)) { hovering = value } }
        .animation(AppMotion.quick(reduceMotion: reduceMotion), value: phase)
    }

    @ViewBuilder private var actionControl: some View {
        if phase == .stopping {
            ProgressView().controlSize(.small).frame(width: 24).help("Stopping")
        } else {
            Button(actionTitle, systemImage: actionSymbol) { performAction() }
                .labelStyle(.iconOnly).buttonStyle(.borderless).foregroundStyle(actionColor)
                .frame(width: 24, height: 24).contentShape(Rectangle())
                .help(actionHelp).accessibilityLabel(actionHelp)
        }
    }

    private func performAction() {
        switch phase {
        case .stopped: model.start(profile)
        case .starting, .running: model.stop(profile)
        case .stopping: break
        case .failed:
            let text = model.acknowledgeFailureAndReturnLogs(for: profile.id)
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
        }
    }

    private var actionTitle: String { phase.isFailed ? "Copy logs" : phase.isActive ? "Stop" : "Start" }
    private var actionSymbol: String { phase.isFailed ? "square.on.square" : phase.isActive ? "stop.fill" : "play.fill" }
    private var actionHelp: String { phase.isFailed ? "Copy logs and reset \(profile.name)" : "\(actionTitle) \(profile.name)" }
    private var actionColor: Color { phase.isFailed ? .red : phase.isActive ? .red : .green }
    private var subtitle: String {
        if phase.isFailed { return "Failed — copy logs to reset" }
        let value = profile.description.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? phase.title : value
    }
    private var statusColor: Color {
        switch phase { case .running: .green; case .starting, .stopping: .orange; case .failed: .red; case .stopped: .secondary }
    }
}
