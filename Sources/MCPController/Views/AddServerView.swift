import SwiftUI

struct AddServerView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var profile = ServerProfile()

    var body: some View {
        NavigationStack {
            Form {
                TextField("Server name", text: $profile.name)
                TextField("Executable path", text: $profile.executablePath)
                TextField("Working directory", text: $profile.workingDirectory)
                Stepper("Local HTTP port: \(profile.localPort)", value: $profile.localPort, in: 1...65535)
                Picker("Exposure", selection: $profile.exposureMode) {
                    ForEach(ExposureMode.allCases) { mode in Text(mode.title).tag(mode) }
                }
                if profile.exposureMode != .disabled {
                    TextField("Mount path", text: $profile.mountPath)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add MCP Server")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        model.add(profile)
                        dismiss()
                    }
                    .disabled(profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .frame(width: 520, height: 420)
    }
}
