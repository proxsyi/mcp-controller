import SwiftUI

struct AddServerView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var profile = ServerProfile()
    @State private var localPortText = ""
    @State private var suggestedPort = 4100
    @State private var appliedDefaults = false

    private var resolvedLocalPort: Int? {
        let trimmed = localPortText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return suggestedPort }
        guard let port = Int(trimmed), (1024...65535).contains(port) else { return nil }
        return port
    }
    private var canAdd: Bool {
        !profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !profile.executablePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && resolvedLocalPort != nil &&
        !model.serverProfiles.contains(where: { $0.localPort == resolvedLocalPort })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 10) {
                        Image(systemName: "server.rack").font(.system(size: 28, weight: .semibold)).frame(width: 62, height: 62)
                            .liquidGlass(.clear, cornerRadius: 22, interactive: true)
                        Text("Connect a server").font(.title2.weight(.semibold))
                        Text("Add its executable now. Networking and access can be configured afterward.")
                            .foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    ContentCard(title: "Server", symbol: "terminal") {
                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 14) {
                            GridRow { Text("Name").foregroundStyle(.secondary); TextField("Desktop control", text: $profile.name) }
                            GridRow { Text("Description").foregroundStyle(.secondary); TextField("What this server does", text: $profile.description) }
                            GridRow { Text("Executable").foregroundStyle(.secondary); TextField("/absolute/path/to/executable", text: $profile.executablePath) }
                            GridRow { Text("Working folder").foregroundStyle(.secondary); TextField("Optional", text: $profile.workingDirectory) }
                        }.textFieldStyle(.roundedBorder)
                    }
                    ContentCard(title: "Local connection", symbol: "network") {
                        VStack(alignment: .leading, spacing: 8) {
                            LabeledContent("MCP server port") {
                                TextField(String(suggestedPort), text: $localPortText).textFieldStyle(.roundedBorder).frame(width: 110)
                                    .onChange(of: localPortText) { _, value in localPortText = value.filter(\.isNumber) }
                            }
                            Text(localPortText.isEmpty ? "Suggested available port: \(suggestedPort)" : "Use port 1024 or higher. The server will listen on this Mac only until you configure exposure.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }.padding(28)
            }
            .navigationTitle("Add MCP Server")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add Server", systemImage: "plus") {
                        profile.localPort = resolvedLocalPort ?? suggestedPort
                        profile.gatewayPort = model.nextAvailableGatewayPort(startingAt: min(profile.localPort + 1, 65_535))
                        profile.mountPath = model.uniqueMountPath(for: profile.name)
                        profile.tailscalePath = TailscaleRouteService.defaultCLIPath
                        model.add(profile); dismiss()
                    }.buttonStyle(.borderedProminent).disabled(!canAdd)
                }
            }
        }
        .frame(width: 660, height: 610)
        .onAppear {
            guard !appliedDefaults else { return }
            appliedDefaults = true
            profile = model.defaultProfileTemplate()
            suggestedPort = profile.localPort
            profile.tailscalePath = TailscaleRouteService.defaultCLIPath
            if settings.oneAIOnly {
                profile.exclusiveGatewayEnabled = true
                if profile.clientCredentials.isEmpty {
                    profile.clientCredentials = [.generate(name: "Primary AI")]
                }
            }
        }
    }
}
