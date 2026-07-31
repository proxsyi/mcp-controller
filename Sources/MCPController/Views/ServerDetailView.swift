import SwiftUI
import AppKit

private enum DetailSection: String, CaseIterable, Identifiable {
    case setup = "Setup"
    case access = "Access"
    case activity = "Activity"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .setup: return "slider.horizontal.3"
        case .access: return "globe"
        case .activity: return "text.alignleft"
        }
    }
}

struct ServerDetailView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draft: ServerProfile
    @State private var argumentsText: String
    @State private var environmentText: String
    @State private var savedProfile: ServerProfile
    @State private var selection: DetailSection = .setup
    @State private var pulse = false
    @State private var showingRestartConfirmation = false
    @State private var isSynchronizingDraft = false

    private let settingColumns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    init(profile: ServerProfile) {
        _draft = State(initialValue: profile)
        _argumentsText = State(initialValue: profile.arguments.joined(separator: "\n"))
        _environmentText = State(initialValue: profile.environment.sorted(by: { $0.key < $1.key }).map { "\($0.key)=\($0.value)" }.joined(separator: "\n"))
        _savedProfile = State(initialValue: profile)
    }

    private var phase: RuntimePhase { model.phase(for: draft.id) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.45)
            if hasPendingRunningChanges {
                pendingChangesBanner
            }
            ScrollView {
                VStack(spacing: 18) {
                    Picker("Server tabs", selection: $selection) {
                        ForEach(DetailSection.allCases) { section in
                            Label(section.rawValue, systemImage: section.symbol).tag(section)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 520)
                    .padding(.bottom, 2)

                    selectedContent
                        .id(selection)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
                .frame(maxWidth: 820)
                .padding(.horizontal, 32)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
            }
            .animation(AppMotion.standard(reduceMotion: reduceMotion), value: selection)
        }
        .onChange(of: draft) { _, _ in saveDraft() }
        .onChange(of: argumentsText) { _, _ in saveDraft() }
        .onChange(of: environmentText) { _, _ in saveDraft() }
        .onChange(of: phase) { _, value in handlePhaseChange(value) }
        .onAppear { updatePulse(for: phase) }
        .alert("Restart server to apply changes?", isPresented: $showingRestartConfirmation) {
            Button("Cancel Changes", role: .cancel) { revertDraft() }
            Button("Restart & Apply", role: .destructive) { applyDraftAndRestart() }
        } message: {
            Text("\(savedProfile.name) is running. MCP Controller will stop it, save these changes, and start it again.")
        }
    }

    private var hasPendingRunningChanges: Bool {
        phase.isActive && draft != savedProfile
    }

    private var pendingChangesBanner: some View {
        HStack(spacing: 12) {
            Label("Unsaved changes require a restart", systemImage: "arrow.clockwise.circle")
                .font(.subheadline.weight(.medium))
            Spacer()
            Button("Discard") { revertDraft() }
            Button("Apply & Restart") { showingRestartConfirmation = true }
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.1))
    }

    private var header: some View {
        HStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.16))
                    .frame(width: 52, height: 52)
                    .scaleEffect(pulse ? 1.08 : 1)
                Image(systemName: "server.rack")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(statusColor)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(draft.name)
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 9) {
                    StatusPill(phase: phase)
                    Text(endpointSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            actionGroup
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 19)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.82))
    }

    private var actionGroup: some View {
        HStack(spacing: 10) {
            actionCircle(symbol: "plus.square.on.square", tint: .secondary, help: "Duplicate server") {
                model.duplicate(draft)
            }
            actionCircle(symbol: "arrow.uturn.left.circle.fill", tint: model.lease(for: draft.id) == nil ? .secondary : .orange, help: model.lease(for: draft.id) == nil ? "No active AI lease" : "Release AI lease") {
                model.releaseLease(profileID: draft.id)
            }
            .disabled(model.lease(for: draft.id) == nil)
            if phase.isActive {
                actionCircle(symbol: "stop.fill", tint: .red, help: "Stop server") {
                    model.stop(draft)
                }
            } else {
                actionCircle(symbol: "play.fill", tint: .blue, help: "Start server") {
                    saveDraft()
                    model.start(draft)
                }
            }
        }
    }

    @ViewBuilder private var selectedContent: some View {
        switch selection {
        case .setup:
            setupContent
        case .access:
            ExposureSettingsView(profile: $draft, phase: phase, persistLiveChange: syncLiveProfile)
        case .activity:
            logsContent
        }
    }

    private var setupContent: some View {
        VStack(spacing: 18) {
            ContentCard(title: "Basics", symbol: "server.rack") {
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 14) {
                    GridRow {
                        Text("Name").foregroundStyle(.secondary)
                        TextField("Server name", text: $draft.name)
                    }
                    GridRow {
                        Text("Description").foregroundStyle(.secondary)
                        TextField("What this server is for", text: $draft.description)
                    }
                }
                .textFieldStyle(.roundedBorder)
            }

            ContentCard(title: "Launch", symbol: "terminal") {
                VStack(alignment: .leading, spacing: 12) {
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 14) {
                        GridRow {
                            Text("Executable").foregroundStyle(.secondary)
                            TextField("/absolute/path/to/executable", text: $draft.executablePath)
                        }
                        GridRow {
                            Text("Working folder").foregroundStyle(.secondary)
                            TextField("Optional", text: $draft.workingDirectory)
                        }
                    }
                    .textFieldStyle(.roundedBorder)

                    Divider().padding(.vertical, 2)

                    Text("Arguments")
                        .font(.subheadline.weight(.medium))
                    TextEditor(text: $argumentsText)
                        .font(.system(.body, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .frame(minHeight: 104)
                        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                    Text("One argument per line. Use {port} to insert the configured local port.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Divider().padding(.vertical, 2)

                    Text("Environment")
                        .font(.subheadline.weight(.medium))
                    TextEditor(text: $environmentText)
                        .font(.system(.body, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .frame(minHeight: 88)
                        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                    Text("One KEY=value pair per line. Values stay in the local app configuration.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            ContentCard(title: "Local behavior", symbol: "slider.horizontal.3") {
                LazyVGrid(columns: settingColumns, alignment: .leading, spacing: 12) {
                    settingTile("Local endpoint", detail: phase.isActive ? "Stop the server before changing the port" : "Server listens on this Mac only", symbol: "network") {
                        HStack(spacing: 8) {
                            Text("127.0.0.1:")
                                .font(.system(.subheadline, design: .monospaced))
                                .foregroundStyle(.secondary)
                            TextField("4101", text: integerBinding(\.localPort))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 88)
                        }
                    }

                    settingTile("Readiness timeout", detail: "How long MCP Controller waits for the port to open", symbol: "timer") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("\(Int(readinessTimeoutBinding.wrappedValue))s")
                                    .font(.system(.headline, design: .monospaced))
                                Spacer()
                            }
                            Slider(value: readinessTimeoutBinding, in: 15...60, step: 1)
                        }
                    }

                    settingTile("Remote path", detail: draft.tailscaleRouteEnabled ? "Used when remote access is on" : "Used the next time remote access is enabled", symbol: "point.3.connected.trianglepath.dotted") {
                        TextField("/mcp/server", text: $draft.mountPath)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.subheadline, design: .monospaced))
                    }

                    settingTile("Start at launch", detail: draft.autoStart ? "Starts when MCP Controller opens" : "Stays stopped until you start it", symbol: draft.autoStart ? "play.circle.fill" : "pause.circle") {
                        Toggle("Start when MCP Controller opens", isOn: $draft.autoStart)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                }

                if draft.localPort < 1024 {
                    Label("Use port 1024 or higher.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.red)
                        .padding(.top, 8)
                }
            }
        }
    }

    private var logsContent: some View {
        ContentCard(title: "Logs", symbol: "text.alignleft") {
            VStack(alignment: .leading, spacing: 12) {
                ScrollView {
                    Text(model.logs[draft.id, default: "No output yet."])
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                }
                .frame(minHeight: 340)
                .background(Color.black.opacity(0.86), in: RoundedRectangle(cornerRadius: 13))
                .foregroundStyle(Color.white.opacity(0.88))

                HStack {
                    Text("The newest 100 KB is kept in memory.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Copy logs", systemImage: "square.on.square") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(model.logs[draft.id, default: ""], forType: .string)
                    }
                    .labelStyle(.iconOnly)
                    .help("Copy logs")
                    Button("Clear", systemImage: "trash") { model.clearLog(for: draft.id) }
                }
            }
        }
    }

    private var endpointSummary: String {
        let access = draft.exclusiveGatewayEnabled ? "Protected" : "Direct"
        return "\(access) · 127.0.0.1:\(draft.exposedLocalPort)"
    }

    private var readinessTimeoutBinding: Binding<Double> {
        Binding(
            get: { max(15, draft.startupDelaySeconds) },
            set: { draft.startupDelaySeconds = min(max($0, 15), 60) }
        )
    }

    private var statusColor: Color {
        switch phase {
        case .running: return .green
        case .starting, .stopping: return .orange
        case .failed: return .red
        case .stopped: return .secondary
        }
    }

    private func handlePhaseChange(_ phase: RuntimePhase) {
        updatePulse(for: phase)
        if !phase.isActive, draft != savedProfile {
            model.update(draft)
            savedProfile = draft
        }
    }

    private func updatePulse(for phase: RuntimePhase) {
        pulse = false
        guard phase.isActive, !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 1.35).repeatForever(autoreverses: true)) { pulse = true }
    }

    private func saveDraft() {
        guard !isSynchronizingDraft else { return }
        draft.arguments = argumentsText.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        draft.environment = environmentText.split(separator: "\n").reduce(into: [:]) { values, line in
            guard let split = line.firstIndex(of: "=") else { return }
            values[String(line[..<split])] = String(line[line.index(after: split)...])
        }
        guard draft != savedProfile else { return }
        if !phase.isActive {
            model.update(draft)
            savedProfile = draft
        }
    }

    private func applyDraftAndRestart() {
        let original = savedProfile
        let updated = draft
        showingRestartConfirmation = false
        model.update(updated)
        savedProfile = updated
        model.stop(original) { [weak model] in model?.start(updated) }
    }

    private func revertDraft() {
        showingRestartConfirmation = false
        isSynchronizingDraft = true
        draft = savedProfile
        argumentsText = savedProfile.arguments.joined(separator: "\n")
        environmentText = savedProfile.environment.sorted(by: { $0.key < $1.key }).map { "\($0.key)=\($0.value)" }.joined(separator: "\n")
        Task { @MainActor in
            await Task.yield()
            isSynchronizingDraft = false
        }
    }

    private func syncLiveProfile(_ profile: ServerProfile) {
        isSynchronizingDraft = true
        draft = profile
        savedProfile = profile
        Task { @MainActor in
            await Task.yield()
            isSynchronizingDraft = false
        }
    }

    private func settingTile<Content: View>(_ title: String, detail: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            content()
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(14)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
    }

    private func actionCircle(symbol: String, tint: Color, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
        }
        .buttonStyle(PerfectCircleToolbarButtonStyle())
        .help(help)
    }

    private func integerBinding(_ keyPath: WritableKeyPath<ServerProfile, Int>) -> Binding<String> {
        Binding(
            get: { String(draft[keyPath: keyPath]) },
            set: { text in
                let digits = text.filter(\.isNumber)
                if let value = Int(digits), (1024...65535).contains(value) {
                    draft[keyPath: keyPath] = value
                }
            }
        )
    }
}
