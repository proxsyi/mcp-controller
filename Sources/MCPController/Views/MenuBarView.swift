import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("MCP Controller").font(.headline)
                    Text(model.runningCount == 0 ? "Everything is stopped" : "\(model.runningCount) running")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
                Spacer()
                Image(systemName: model.runningCount > 0 ? "bolt.fill" : "bolt")
                    .foregroundStyle(model.runningCount > 0 ? .green : .secondary)
            }
            Divider()
            if model.profiles.isEmpty {
                Label("No servers configured", systemImage: "server.rack")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(model.profiles) { profile in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(statusColor(model.phase(for: profile.id)))
                            .frame(width: 7, height: 7)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.name).lineLimit(1)
                            Text(profile.exposureMode.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if model.phase(for: profile.id).isActive {
                            Button("Stop") { model.stop(profile) }
                                .controlSize(.small)
                        } else {
                            Button("Start") { model.start(profile) }
                                .controlSize(.small)
                        }
                    }
                    .padding(.vertical, 3)
                }
                Divider()
                Button("Stop Everything", systemImage: "stop.fill", role: .destructive) { model.stopAll() }
                    .disabled(model.runningCount == 0)
            }
        }
        .padding(14)
        .frame(width: 340)
    }

    private func statusColor(_ phase: RuntimePhase) -> Color {
        switch phase {
        case .running: .green
        case .starting, .stopping: .orange
        case .failed: .red
        case .stopped: .secondary
        }
    }
}
