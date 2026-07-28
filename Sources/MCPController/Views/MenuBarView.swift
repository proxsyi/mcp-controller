import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("MCP Controller")
                    .font(.headline)
                Spacer()
                Text(model.runningCount == 0 ? "Stopped" : "\(model.runningCount) running")
                    .font(.caption)
                    .foregroundStyle(model.runningCount > 0 ? .green : .secondary)
                    .contentTransition(.numericText())
            }

            Divider()

            if model.profiles.isEmpty {
                Label("No servers configured", systemImage: "server.rack")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(model.profiles) { profile in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(statusColor(model.phase(for: profile.id)))
                                    .frame(width: 7, height: 7)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(profile.name)
                                        .font(.callout.weight(.medium))
                                        .lineLimit(1)
                                    Text(subtitle(for: profile))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 6)
                                Button {
                                    model.phase(for: profile.id).isActive ? model.stop(profile) : model.start(profile)
                                } label: {
                                    Image(systemName: model.phase(for: profile.id).isActive ? "stop.fill" : "play.fill")
                                        .frame(width: 18, height: 18)
                                }
                                .buttonStyle(.borderless)
                                .help(model.phase(for: profile.id).isActive ? "Stop \(profile.name)" : "Start \(profile.name)")
                            }
                            .frame(height: 38)
                        }
                    }
                }
                .frame(maxHeight: 240)

                Divider()

                Button("Stop Everything", systemImage: "stop.fill", role: .destructive) {
                    model.stopAll()
                }
                .controlSize(.small)
                .disabled(model.runningCount == 0)
            }
        }
        .padding(10)
        .frame(width: 300)
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
