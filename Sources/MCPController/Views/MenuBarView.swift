import SwiftUI
import AppKit

struct MenuBarView: View {
    @EnvironmentObject private var model: AppModel

    private var menuHeight: CGFloat {
        min(model.profiles.reduce(CGFloat(0)) { partial, profile in
            partial + (profile.isServer ? 42 : profile.isHeading ? 24 : 12)
        }, 280)
    }

    private var statusSummary: String {
        if model.failedCount > 0 {
            return "\(model.failedCount) failed"
        }
        if model.runningCount > 0 {
            return "\(model.runningCount) running"
        }
        if model.activeCount > 0 {
            return "\(model.activeCount) starting"
        }
        return "Stopped"
    }

    private var statusColor: Color {
        if model.failedCount > 0 { return .red }
        if model.runningCount > 0 { return .green }
        if model.activeCount > 0 { return .orange }
        return .secondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("MCP Controller").font(.headline)
                Spacer()
                Text(statusSummary)
                    .font(.caption)
                    .foregroundStyle(statusColor)
                    .contentTransition(.numericText())
            }
            Divider()
            if model.profiles.isEmpty {
                Label("No items configured", systemImage: "server.rack")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(model.profiles) { profile in
                            menuRow(profile)
                        }
                    }
                }
                .frame(height: menuHeight)
                Divider()
                HStack(spacing: 8) {
                    Button("Stop Everything", systemImage: "stop.fill", role: .destructive) { model.stopAll() }
                        .controlSize(.small)
                        .disabled(model.activeCount == 0 || model.isProcessingBulkLifecycleAction)
                    Button("Start Everything", systemImage: "play.fill") { model.startAll() }
                        .controlSize(.small)
                        .disabled(model.serverProfiles.isEmpty || model.serverProfiles.allSatisfy { model.phase(for: $0.id).isActive } || model.isProcessingBulkLifecycleAction)
                    Button("Release All", systemImage: "arrow.uturn.left.circle") { model.releaseAllLeases() }
                        .controlSize(.small)
                        .disabled(model.activeLeaseCount == 0)
                }
            }
        }
        .padding(10)
        .frame(width: 390)
    }

    @ViewBuilder
    private func menuRow(_ profile: ServerProfile) -> some View {
        if profile.isHeading {
            Text(profile.name)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
                .padding(.bottom, 2)
        } else if profile.isSpacer {
            Divider().padding(.vertical, 3)
        } else {
            serverRow(profile)
        }
    }

    private func serverRow(_ profile: ServerProfile) -> some View {
        let phase = model.phase(for: profile.id)
        let hasLease = model.lease(for: profile.id) != nil
        return HStack(spacing: 8) {
            Circle().fill(statusColor(for: phase)).frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(profile.name).font(.callout.weight(.medium)).lineLimit(1)
                Text(phase.isFailed ? "Failed — copy logs to reset" : subtitle(for: profile)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            if phase == .stopping {
                ProgressView().controlSize(.small).frame(width: 54)
            } else {
                HStack(spacing: 6) {
                    Button {
                        model.releaseLease(profileID: profile.id)
                    } label: {
                        Image(systemName: "arrow.uturn.left.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(hasLease ? Color.orange : Color.secondary.opacity(0.4))
                    .background(Circle().fill((hasLease ? Color.orange : Color.secondary).opacity(hasLease ? 0.16 : 0.08)))
                    .clipShape(Circle())
                    .help(hasLease ? "Release AI lease" : "No active AI lease")
                    .disabled(!hasLease)

                    Button(phase.isFailed ? "Copy" : phase.isActive ? "Stop" : "Start", systemImage: phase.isFailed ? "square.on.square" : phase.isActive ? "stop.fill" : "play.fill") {
                        if phase.isFailed {
                            let text = model.acknowledgeFailureAndReturnLogs(for: profile.id)
                            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
                        } else if phase.isActive {
                            model.stop(profile)
                        } else {
                            model.start(profile)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(phase.isFailed || phase.isActive ? .red : .accentColor)
                    .fixedSize()
                }
            }
        }
        .frame(height: 42)
    }

    private func subtitle(for profile: ServerProfile) -> String {
        let value = profile.description.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? model.phase(for: profile.id).title : value
    }

    private func statusColor(for phase: RuntimePhase) -> Color {
        switch phase {
        case .running: .green
        case .starting, .stopping: .orange
        case .failed: .red
        case .stopped: .secondary
        }
    }
}
