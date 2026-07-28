import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("MCP Controller")
                        .font(.headline)
                    Text(model.runningCount == 0 ? "Everything is stopped" : "\(model.runningCount) running")
                        .font(.caption2)
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
                    .padding(.vertical, 6)
            } else {
                ForEach(model.profiles) { profile in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(statusColor(model.phase(for: profile.id)))
                            .frame(width: 7, height: 7)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(profile.name)
                                .lineLimit(1)
                            Text(subtitle(for: profile))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 6)
                        Button {
                            model.phase(for: profile.id).isActive ? model.stop(profile) : model.start(profile)
                        } label: {
                            Image(systemName: model.phase(for: profile.id).isActive ? "stop.fill" : "play.fill")
                        }
                        .buttonStyle(.borderless)
                        .help(model.phase(for: profile.id).isActive ? "Stop \(profile.name)" : "Start \(profile.name)")
                    }
                    .padding(.vertical, 2)
                }
                Divider()
                Button("Stop Everything", systemImage: "stop.fill", role: .destructive) { model.stopAll() }
                    .disabled(model.runningCount == 0)
            }
        }
        .padding(12)
        .frame(width: 292)
    }

    private func subtitle(for profile: ServerProfile) -> String {
        let trimmed = profile.description.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? profile.exposureMode.title : trimmed
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
