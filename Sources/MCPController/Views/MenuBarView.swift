import SwiftUI
import AppKit

struct MenuBarView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("MCP Controller").font(.headline)
                Spacer()
                if model.failedCount > 0 {
                    Text("\(model.failedCount) failed").font(.caption).foregroundStyle(.red)
                } else {
                    Text(model.runningCount == 0 ? "Stopped" : "\(model.runningCount) running")
                        .font(.caption).foregroundStyle(model.runningCount > 0 ? .green : .secondary).contentTransition(.numericText())
                }
            }
            Divider()
            if model.profiles.isEmpty {
                Label("No servers configured", systemImage: "server.rack").font(.callout).foregroundStyle(.secondary).padding(.vertical, 4)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) { ForEach(model.profiles) { serverRow($0) } }
                }.frame(height: min(CGFloat(model.profiles.count) * 44, 240))
                if model.runningCount > 0 {
                    Divider()
                    Button("Stop Everything", systemImage: "stop.fill", role: .destructive) { model.stopAll() }.controlSize(.small)
                }
            }
        }.padding(10).frame(width: 340)
    }

    private func serverRow(_ profile: ServerProfile) -> some View {
        let phase = model.phase(for: profile.id)
        return HStack(spacing: 8) {
            Circle().fill(statusColor(phase)).frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(profile.name).font(.callout.weight(.medium)).lineLimit(1)
                Text(phase.isFailed ? "Failed — copy logs to reset" : subtitle(for: profile)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            if phase == .stopping {
                ProgressView().controlSize(.small).frame(width: 54)
            } else {
                Button(phase.isFailed ? "Copy" : phase.isActive ? "Stop" : "Start", systemImage: phase.isFailed ? "square.on.square" : phase.isActive ? "stop.fill" : "play.fill") {
                    if phase.isFailed {
                        let text = model.acknowledgeFailureAndReturnLogs(for: profile.id)
                        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
                    } else if phase.isActive { model.stop(profile) } else { model.start(profile) }
                }
                .buttonStyle(.bordered).controlSize(.small).tint(phase.isFailed || phase.isActive ? .red : .accentColor).fixedSize()
            }
        }.frame(height: 42)
    }

    private func subtitle(for profile: ServerProfile) -> String {
        let value = profile.description.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? model.phase(for: profile.id).title : value
    }
    private func statusColor(_ phase: RuntimePhase) -> Color {
        switch phase { case .running: .green; case .starting, .stopping: .orange; case .failed: .red; case .stopped: .secondary }
    }
}
