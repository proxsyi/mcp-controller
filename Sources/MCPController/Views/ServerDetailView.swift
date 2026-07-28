import SwiftUI

struct ServerDetailView: View {
    @EnvironmentObject private var model: AppModel
    @State private var draft: ServerProfile
    @State private var argumentsText: String
    @State private var environmentText: String

    init(profile: ServerProfile) {
        _draft = State(initialValue: profile)
        _argumentsText = State(initialValue: profile.arguments.joined(separator: "\n"))
        _environmentText = State(initialValue: profile.environment.sorted(by: { $0.key < $1.key }).map { "\($0.key)=\($0.value)" }.joined(separator: "\n"))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Form {
                Section("Server process") {
                    TextField("Name", text: $draft.name)
                    LabeledContent("Executable") {
                        TextField("/absolute/path/to/executable", text: $draft.executablePath)
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("Working directory") {
                        TextField("Optional", text: $draft.workingDirectory)
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("Arguments") {
                        TextEditor(text: $argumentsText)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 80)
                    }
                    Text("Enter one argument per line. Use {port} where the configured local port should be inserted.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    LabeledContent("Environment") {
                        TextEditor(text: $environmentText)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 70)
                    }
                    Text("Enter KEY=value pairs, one per line. Secrets remain in the local app configuration and should not be committed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Endpoint and exposure") {
                    Stepper("Local HTTP port: \(draft.localPort)", value: $draft.localPort, in: 1...65535)
                    Picker("Exposure", selection: $draft.exposureMode) {
                        ForEach(ExposureMode.allCases) { mode in Text(mode.title).tag(mode) }
                    }
                    if draft.exposureMode != .disabled {
                        Picker("Public HTTPS port", selection: $draft.publicPort) {
                            ForEach([443, 8443, 10000], id: \.self) { Text(String($0)).tag($0) }
                        }
                        TextField("Mount path", text: $draft.mountPath)
                        TextField("Tailscale CLI", text: $draft.tailscalePath)
                    }
                    Stepper("Startup delay: \(draft.startupDelaySeconds, specifier: "%.1f") seconds", value: $draft.startupDelaySeconds, in: 0...30, step: 0.5)
                    Toggle("Start when MCP Controller opens", isOn: $draft.autoStart)
                }

                Section("Runtime log") {
                    ScrollView {
                        Text(model.logs[draft.id, default: "No output yet."])
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 160)
                    Button("Clear log") { model.clearLog(for: draft.id) }
                }
            }
            .formStyle(.grouped)
        }
        .onChange(of: draft) { _, _ in saveDraft() }
        .onChange(of: argumentsText) { _, _ in saveDraft() }
        .onChange(of: environmentText) { _, _ in saveDraft() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(draft.name).font(.title2).fontWeight(.semibold)
                Text(model.phase(for: draft.id).title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.phase(for: draft.id).isActive {
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
        .padding(20)
    }

    private func saveDraft() {
        draft.arguments = argumentsText.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        draft.environment = Dictionary(uniqueKeysWithValues: environmentText.split(separator: "\n").compactMap { line in
            guard let split = line.firstIndex(of: "=") else { return nil }
            return (String(line[..<split]), String(line[line.index(after: split)...]))
        })
        model.update(draft)
    }
}
