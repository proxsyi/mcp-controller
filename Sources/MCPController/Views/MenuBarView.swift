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
                            serverRow(profile)
                        }
                    }
                }
                .frame(height: min(CGFloat(model.profiles.count) * 44, 240))

                if model.runningCount > 0 {
                    Divider()
                    Button("Stop Everything", systemImage: "stop.fill", role: .destructive) {
                        model.stopAll()
                    }
                    .controlSize(.small)
                }
            }
        }
        .padding(10)
        .frame(width: 320)
    }

    private func serverRow(_ profile: ServerProfile) -> some View {
        let active = model.phase(for: profile.id).isActive
        return HStack(spacing: 8) {
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
            Spacer(minLength: 8)
            Button(active ? "Stop" : "Start", systemImage: active ? "stop.fill" : "play.fill") {
                active ? model.stop(profile) : model.start(profile)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(active ? .red : .accentColor)
            .fixedSize()
        }
        .frame(height: 42)
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
