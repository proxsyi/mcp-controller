import SwiftUI

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
            $0.exposureMode.title.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $model.selectedID) {
                Section {
                    ForEach(filteredProfiles) { profile in
                        ServerRow(profile: profile, phase: model.phase(for: profile.id))
                            .tag(profile.id)
                            .contextMenu {
                                Button("Start", systemImage: "play.fill") { model.start(profile) }.disabled(model.phase(for: profile.id).isActive)
                                Button("Stop", systemImage: "stop.fill") { model.stop(profile) }.disabled(!model.phase(for: profile.id).isActive)
                                Divider()
                                Button("Duplicate", systemImage: "plus.square.on.square") { model.duplicate(profile) }
                                Button("Remove", systemImage: "trash", role: .destructive) { model.remove(profile) }
                            }
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
                        Text("Add an MCP server or HTTP bridge. You control when it runs and where it is exposed.")
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
                Button("Add server", systemImage: "plus") { showingAddServer = true }
                    .help("Add an MCP server")
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Settings (⌘,)")
            }
        }
        .sheet(isPresented: $showingAddServer) { AddServerView().environmentObject(model) }
        .alert("MCP Controller", isPresented: Binding(get: { model.presentedError != nil }, set: { if !$0 { model.presentedError = nil } })) {
            Button("OK") { model.presentedError = nil }
        } message: { Text(model.presentedError ?? "") }
    }

    private var sidebarSummary: some View {
        HStack {
            Text(model.profiles.isEmpty ? "Configured" : "\(model.profiles.count) configured")
            Spacer(minLength: 16)
            if model.runningCount > 0 {
                Label("\(model.runningCount)", systemImage: "bolt.fill")
                    .font(.caption.weight(.semibold)).foregroundStyle(.green).contentTransition(.numericText()).fixedSize()
            }
        }
        .textCase(nil).font(.caption).foregroundStyle(.secondary).padding(.vertical, 4).padding(.trailing, 12)
    }
}

private struct ServerRow: View {
    let profile: ServerProfile
    let phase: RuntimePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 11) {
            ZStack {
                Circle().fill(statusColor.opacity(0.16)).frame(width: 30, height: 30)
                Image(systemName: profile.exposureMode == .funnel ? "globe" : profile.exposureMode == .tailnet ? "point.3.connected.trianglepath.dotted" : "server.rack")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(statusColor)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(profile.name).fontWeight(.medium).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 8)
            Circle().fill(statusColor).frame(width: 7, height: 7).accessibilityLabel(phase.title)
        }
        .padding(.vertical, 5).contentShape(Rectangle()).scaleEffect(hovering && !reduceMotion ? 1.012 : 1)
        .onHover { value in withAnimation(AppMotion.quick(reduceMotion: reduceMotion)) { hovering = value } }
    }

    private var subtitle: String {
        let trimmed = profile.description.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? profile.exposureMode.title : trimmed
    }
    private var statusColor: Color {
        switch phase { case .running: .green; case .starting, .stopping: .orange; case .failed: .red; case .stopped: .secondary }
    }
}
