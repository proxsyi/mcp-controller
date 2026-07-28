import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingAddServer = false

    var body: some View {
        NavigationSplitView {
            List(selection: $model.selectedID) {
                ForEach(model.profiles) { profile in
                    ServerRow(profile: profile, phase: model.phase(for: profile.id))
                        .tag(profile.id)
                        .contextMenu {
                            Button("Duplicate") { model.duplicate(profile) }
                            Divider()
                            Button("Remove", role: .destructive) { model.remove(profile) }
                        }
                }
            }
            .navigationTitle("MCP Servers")
            .overlay {
                if model.profiles.isEmpty {
                    ContentUnavailableView("No servers", systemImage: "server.rack", description: Text("Add an MCP server or HTTP bridge to begin."))
                }
            }
            .toolbar {
                ToolbarItem {
                    Button("Add server", systemImage: "plus") { showingAddServer = true }
                }
            }
        } detail: {
            if let id = model.selectedID,
               let profile = model.profiles.first(where: { $0.id == id }) {
                ServerDetailView(profile: profile)
                    .id(profile.id)
            } else {
                ContentUnavailableView("Select a server", systemImage: "slider.horizontal.3")
            }
        }
        .sheet(isPresented: $showingAddServer) {
            AddServerView()
                .environmentObject(model)
        }
        .alert("MCP Controller", isPresented: Binding(get: { model.presentedError != nil }, set: { if !$0 { model.presentedError = nil } })) {
            Button("OK") { model.presentedError = nil }
        } message: {
            Text(model.presentedError ?? "")
        }
    }
}

private struct ServerRow: View {
    let profile: ServerProfile
    let phase: RuntimePhase

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name).fontWeight(.medium)
                Text(profile.exposureMode.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch phase {
        case .running: .green
        case .starting, .stopping: .orange
        case .failed: .red
        case .stopped: .secondary
        }
    }
}
