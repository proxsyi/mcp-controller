import SwiftUI

private enum DetailSection: String, CaseIterable, Identifiable {
    case process = "Process"
    case exposure = "Exposure"
    case logs = "Logs"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .process: "terminal"
        case .exposure: "network"
        case .logs: "text.alignleft"
        }
    }
}

struct ServerDetailView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draft: ServerProfile
    @State private var argumentsText: String
    @State private var environmentText: String
    @State private var selection: DetailSection = .process
    @State private var pulse = false
    @Namespace private var actionNamespace

    init(profile: ServerProfile) {
        _draft = State(initialValue: profile)
        _argumentsText = State(initialValue: profile.arguments.joined(separator: "\n"))
        _environmentText = State(initialValue: profile.environment.sorted(by: { $0.key < $1.key }).map { "\($0.key)=\($0.value)" }.joined(separator: "\n"))
    }

    private var phase: RuntimePhase { model.phase(for: draft.id) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.45)
            ScrollView {
                VStack(spacing: 18) {
                    Picker("Server settings", selection: $selection) {
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
        .onChange(of: phase) { _, newPhase in updatePulse(for: newPhase) }
        .onAppear { updatePulse(for: phase) }
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

    @ViewBuilder
    private var actionGroup: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 10) {
                    Button("Duplicate", systemImage: "plus.square.on.square") { model.duplicate(draft) }
                        .buttonStyle(.glass)
                        .glassEffectID("secondary", in: actionNamespace)
                    if phase.isActive {
                        Button("Stop", systemImage: "stop.fill", role: .destructive) { model.stop(draft) }
                            .buttonStyle(.glassProminent)
                            .tint(.red)
                            .glassEffectID("primary", in: actionNamespace)
                            .glassEffectTransition(.matchedGeometry)
                    } else {
                        Button("Start", systemImage: "play.fill") {
                            saveDraft()
                            model.start(draft)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(.blue)
                        .glassEffectID("primary", in: actionNamespace)
                        .glassEffectTransition(.matchedGeometry)
                    }
                }
            }
            .animation(AppMotion.standard(reduceMotion: reduceMotion), value: phase.isActive)
        } else {
            HStack(spacing: 10) {
                Button("Duplicate", systemImage: "plus.square.on.square") { model.duplicate(draft) }
                if phase.isActive {
                    Button("Stop", systemImage: "stop.fill", role: .destructive) { model.stop(draft) }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                } else {
                    Button("Start", systemImage: "play.fill") {
                        saveDraft()
                        model.start(draft)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch selection {
        case .process: processContent
        case .exposure: exposureContent
        case .logs: logsContent
        }
    }

    private var processContent: some View {
        VStack(spacing: 18) {
            ContentCard(title: "Identity", symbol: "server.rack") {
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 14) {
                    GridRow {
                        Text("Name").foregroundStyle(.secondary)
                        TextField("Server name", text: $draft.name)
                    }
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
            }

            ContentCard(title: "Launch configuration", symbol: "terminal") {
                VStack(alignment: .leading, spacing: 9) {
                    Text("Arguments").font(.subheadline.weight(.medium))
                    TextEditor(text: $argumentsText)
                        .font(.system(.body, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .frame(minHeight: 108)
                        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Text("One argument per line. Use {port} to insert the configured local port.")
                        .font(.caption).foregroundStyle(.secondary)
                    Divider().padding(.vertical, 3)
                    Text("Environment").font(.subheadline.weight(.medium))
                    TextEditor(text: $environmentText)
                        .font(.system(.body, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .frame(minHeight: 94)
                        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Text("One KEY=value pair per line. Values stay in the local app configuration.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var exposureContent: some View {
        VStack(spacing: 18) {
            ContentCard(title: "Endpoint", symbol: "point.3.connected.trianglepath.dotted") {
                VStack(alignment: .leading, spacing: 16) {
                    LabeledContent("Local HTTP port") {
                        TextField("Port", value: $draft.localPort, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 110)
                    }
                    Picker("Exposure", selection: $draft.exposureMode) {
                        ForEach(ExposureMode.allCases) { mode in Text(mode.title).tag(mode) }
                    }
                    .pickerStyle(.segmented)
                    Text(exposureExplanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .contentTransition(.interpolate)
                }
            }

            if draft.exposureMode != .disabled {
                ContentCard(title: "Tailscale route", symbol: "shield.lefthalf.filled") {
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 14) {
                        GridRow {
                            Text("HTTPS port").foregroundStyle(.secondary)
                            Picker("HTTPS port", selection: $draft.publicPort) {
                                ForEach([443, 8443, 10000], id: \.self) { Text(String($0)).tag($0) }
                            }.labelsHidden()
                        }
                        GridRow {
                            Text("Mount path").foregroundStyle(.secondary)
                            TextField("/mcp/server", text: $draft.mountPath)
                        }
                        GridRow {
                            Text("Tailscale CLI").foregroundStyle(.secondary)
                            TextField("/usr/local/bin/tailscale", text: $draft.tailscalePath)
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            ContentCard(title: "Behavior", symbol: "timer") {
                VStack(alignment: .leading, spacing: 16) {
                    LabeledContent("Startup delay") {
                        HStack {
                            Slider(value: $draft.startupDelaySeconds, in: 0...30, step: 0.5)
                                .frame(width: 220)
                            Text("\(draft.startupDelaySeconds, specifier: "%.1f")s")
                                .monospacedDigit()
                                .frame(width: 48, alignment: .trailing)
                        }
                    }
                    Toggle("Start when MCP Controller opens", isOn: $draft.autoStart)
                }
            }
        }
        .animation(AppMotion.standard(reduceMotion: reduceMotion), value: draft.exposureMode)
    }

    private var logsContent: some View {
        ContentCard(title: "Runtime output", symbol: "text.alignleft") {
            VStack(alignment: .leading, spacing: 12) {
                ScrollView {
                    Text(model.logs[draft.id, default: "No output yet."])
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                }
                .frame(minHeight: 340)
                .background(Color.black.opacity(0.86), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .foregroundStyle(Color.white.opacity(0.88))
                HStack {
                    Text("The newest 100 KB is kept in memory.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear", systemImage: "trash") { model.clearLog(for: draft.id) }
                }
            }
        }
    }

    private var endpointSummary: String {
        switch draft.exposureMode {
        case .disabled: "Local · 127.0.0.1:\(draft.localPort)"
        case .tailnet: "Tailnet · \(draft.normalizedMountPath)"
        case .funnel: "Public Funnel · \(draft.normalizedMountPath)"
        }
    }

    private var exposureExplanation: String {
        switch draft.exposureMode {
        case .disabled: "Only this Mac can reach the endpoint."
        case .tailnet: "Devices in your tailnet can reach the endpoint."
        case .funnel: "The endpoint is public on the internet. Authentication must be enforced by the MCP server or bridge."
        }
    }

    private var statusColor: Color {
        switch phase {
        case .running: .green
        case .starting, .stopping: .orange
        case .failed: .red
        case .stopped: .secondary
        }
    }

    private func updatePulse(for phase: RuntimePhase) {
        pulse = false
        guard phase.isActive, !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 1.35).repeatForever(autoreverses: true)) { pulse = true }
    }

    private func saveDraft() {
        draft.arguments = argumentsText.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        draft.environment = environmentText.split(separator: "\n").reduce(into: [:]) { values, line in
            guard let split = line.firstIndex(of: "=") else { return }
            values[String(line[..<split])] = String(line[line.index(after: split)...])
        }
        model.update(draft)
    }
}
