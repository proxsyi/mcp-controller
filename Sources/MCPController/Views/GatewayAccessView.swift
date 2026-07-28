import SwiftUI
import AppKit

struct GatewayAccessView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var profile: ServerProfile
    let isRunning: Bool
    @State private var originText = ""
    @State private var showKeys = false
    @State private var showAdvanced = false

    var body: some View {
        ContentCard(title: "Access control", symbol: "lock.shield") {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("One AI at a time").fontWeight(.medium)
                        Text(profile.exclusiveGatewayEnabled ? "Protect this route with access keys and an exclusive lease." : "Allow direct remote access without a controller-issued key.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("One AI at a time", isOn: $profile.exclusiveGatewayEnabled)
                        .labelsHidden()
                        .disabled(isRunning)
                }

                if profile.exclusiveGatewayEnabled {
                    compactLeaseStatus

                    DisclosureGroup("Access keys (\(profile.clientCredentials.count))", isExpanded: $showKeys) {
                        credentials.padding(.top, 10)
                    }

                    DisclosureGroup("Advanced gateway settings", isExpanded: $showAdvanced) {
                        advancedSettings.padding(.top, 10)
                    }
                } else {
                    Label("Remote clients connect directly to this server when exposure is enabled.", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if isRunning {
                    Text("Stop the server to change gateway configuration. Access keys can still be copied.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear { originText = profile.allowedOrigins.joined(separator: ", ") }
        .onChange(of: originText) { _, value in
            profile.allowedOrigins = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
    }

    private var compactLeaseStatus: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let lease = model.lease(for: profile.id) {
                HStack {
                    Label("\(lease.clientName) is connected", systemImage: "checkmark.shield.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.green)
                    Spacer()
                    Button("Release") { model.releaseLease(profileID: profile.id) }
                        .controlSize(.small)
                }
            } else {
                Label(profile.remoteClientCompatibilityEnabled ? "Ready for remote clients" : "Ready for a client connection", systemImage: "shield.checkered")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            let waiting = model.waiting(for: profile.id)
            ForEach(waiting) { request in
                HStack {
                    Label("\(request.clientName) is waiting", systemImage: "person.crop.circle.badge.questionmark")
                    Spacer()
                    Button("Deny", role: .destructive) { model.deny(profileID: profile.id, clientID: request.clientID) }
                    Button("Approve") { model.approve(profileID: profile.id, clientID: request.clientID) }
                        .buttonStyle(.borderedProminent)
                }
                .controlSize(.small)
            }
        }
        .padding(.top, 2)
    }

    private var credentials: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach($profile.clientCredentials) { $credential in
                HStack(spacing: 10) {
                    TextField("AI name", text: $credential.name)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                        .disabled(isRunning)
                    Text("••••••••\(credential.token.suffix(6))")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Copy key", systemImage: "square.on.square") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(credential.token, forType: .string)
                    }
                    .labelStyle(.iconOnly)
                    .help("Copy access key")
                    Button("Remove", systemImage: "trash", role: .destructive) {
                        profile.clientCredentials.removeAll { $0.id == credential.id }
                    }
                    .labelStyle(.iconOnly)
                    .disabled(isRunning)
                }
            }

            Button("Add access key", systemImage: "plus") {
                let number = profile.clientCredentials.count + 1
                profile.clientCredentials.append(.generate(name: "AI \(number)"))
            }
            .disabled(isRunning)

            if profile.clientCredentials.isEmpty {
                Label("Add an access key before starting a protected route.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var advancedSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Only change these values if you need a non-default gateway setup.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
                GridRow {
                    Text("Gateway port").foregroundStyle(.secondary)
                    TextField("39000", text: gatewayPortBinding)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                        .disabled(isRunning)
                }
                GridRow {
                    Text("Lease timeout").foregroundStyle(.secondary)
                    Stepper("\(profile.leaseTimeoutSeconds / 60) minutes", value: $profile.leaseTimeoutSeconds, in: 60...86_400, step: 60)
                        .disabled(isRunning)
                }
                GridRow {
                    Text("Allowed origins").foregroundStyle(.secondary)
                    TextField("Optional, comma separated", text: $originText)
                        .textFieldStyle(.roundedBorder)
                        .disabled(isRunning)
                }
            }
        }
    }

    private var gatewayPortBinding: Binding<String> {
        Binding(
            get: { String(profile.gatewayPort) },
            set: { text in
                let digits = text.filter(\.isNumber)
                if let value = Int(digits), (1...65535).contains(value) { profile.gatewayPort = value }
            }
        )
    }
}
