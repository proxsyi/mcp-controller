import SwiftUI

struct AddServerView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var profile = ServerProfile()

    private var canAdd: Bool {
        !profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !profile.executablePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 12) {
                        Image(systemName: "server.rack")
                            .font(.system(size: 28, weight: .semibold))
                            .frame(width: 62, height: 62)
                            .liquidGlass(.clear, cornerRadius: 22, interactive: true)
                        Text("Connect a server")
                            .font(.title2.weight(.semibold))
                        Text("Point MCP Controller at an installed server or HTTP bridge. Nothing is exposed until you choose it.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 430)
                    }
                    .padding(.bottom, 4)

                    ContentCard(title: "Server", symbol: "terminal") {
                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 14) {
                            GridRow {
                                Text("Name").foregroundStyle(.secondary)
                                TextField("Desktop control", text: $profile.name)
                            }
                            GridRow {
                                Text("Description").foregroundStyle(.secondary)
                                TextField("What this server is for", text: $profile.description)
                            }
                            GridRow {
                                Text("Executable").foregroundStyle(.secondary)
                                TextField("/absolute/path/to/executable", text: $profile.executablePath)
                            }
                            GridRow {
                                Text("Working folder").foregroundStyle(.secondary)
                                TextField("Optional", text: $profile.workingDirectory)
                            }
                        }
                        .textFieldStyle(.roundedBorder)
                    }

                    ContentCard(title: "Connection", symbol: "network") {
                        VStack(alignment: .leading, spacing: 16) {
                            LabeledContent("Local HTTP port") {
                                TextField("Port", value: $profile.localPort, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 110)
                            }
                            Picker("Exposure", selection: $profile.exposureMode) {
                                ForEach(ExposureMode.allCases) { mode in Text(mode.title).tag(mode) }
                            }
                            .pickerStyle(.segmented)
                            if profile.exposureMode != .disabled {
                                LabeledContent("Mount path") {
                                    TextField("/mcp/server", text: $profile.mountPath)
                                        .textFieldStyle(.roundedBorder)
                                }
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                    }
                }
                .padding(28)
            }
            .animation(AppMotion.standard(reduceMotion: reduceMotion), value: profile.exposureMode)
            .navigationTitle("Add MCP Server")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add Server", systemImage: "plus") {
                        model.add(profile)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canAdd)
                }
            }
        }
        .frame(width: 660, height: 650)
    }
}
