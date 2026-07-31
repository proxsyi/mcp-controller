import SwiftUI
import AppKit

struct GatewayAccessView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var profile: ServerProfile
    let isRunning: Bool
    @State private var originText = ""
    @State private var showKeys = false

    var body: some View {
        ContentCard(title: "Access control", symbol: "lock.shield") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Protect this route")
                            .fontWeight(.medium)
                        Text(profile.exclusiveGatewayEnabled
                             ? "Remote clients need a controller-issued access key."
                             : "Remote clients connect directly without a controller key.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("Access control", isOn: $profile.exclusiveGatewayEnabled)
                        .labelsHidden()
                }

                if profile.exclusiveGatewayEnabled {
                    leaseSummary

                    if !model.waiting(for: profile.id).isEmpty {
                        waitingRequests
                    }

                    DisclosureGroup("Access keys (\(profile.clientCredentials.count))", isExpanded: $showKeys) {
                        credentials
                            .padding(.top, 8)
                    }

                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                        GridRow {
                            Text("Gateway port").foregroundStyle(.secondary)
                            TextField("39000", text: gatewayPortBinding)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 120)
                        }
                        GridRow {
                            Text("Lease timeout").foregroundStyle(.secondary)
                            Stepper("\(profile.leaseTimeoutSeconds / 60) min", value: $profile.leaseTimeoutSeconds, in: 60...86_400, step: 60)
                        }
                        GridRow {
                            Text("Public request timeout").foregroundStyle(.secondary)
                            Stepper("\(profile.publicRequestTimeoutSeconds / 60) min", value: $profile.publicRequestTimeoutSeconds, in: 60...3_600, step: 60)
                        }
                        GridRow {
                            Text("Allowed origins").foregroundStyle(.secondary)
                            TextField("Optional, comma separated", text: $originText)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }

                if isRunning {
                    Text("Changes stay pending until you confirm Apply & Restart. Access keys can still be copied while it is running.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear { originText = profile.allowedOrigins.joined(separator: ", ") }
        .onChange(of: originText) { _, value in
            profile.allowedOrigins = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        .onChange(of: profile.allowedOrigins) { _, value in
            let normalized = value.joined(separator: ", ")
            if originText != normalized { originText = normalized }
        }
    }

    private var leaseSummary: some View {
        HStack(spacing: 12) {
            Label(leaseTitle, systemImage: leaseSymbol)
                .font(.caption.weight(.medium))
                .foregroundStyle(leaseColor)
            Spacer()
            if model.lease(for: profile.id) != nil {
                Button("Release") { model.releaseLease(profileID: profile.id) }
                    .controlSize(.small)
            }
        }
    }

    private var waitingRequests: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(model.waiting(for: profile.id)) { request in
                HStack(spacing: 10) {
                    Label(request.clientName, systemImage: "person.crop.circle.badge.questionmark")
                        .lineLimit(1)
                    Spacer()
                    Button("Deny", role: .destructive) {
                        model.deny(profileID: profile.id, clientID: request.clientID)
                    }
                    .controlSize(.small)
                    Button("Approve") {
                        model.approve(profileID: profile.id, clientID: request.clientID)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
    }

    private var credentials: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach($profile.clientCredentials) { $credential in
                HStack(spacing: 10) {
                    TextField("Key name", text: $credential.name)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                    Text("••••••••\(credential.token.suffix(6))")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Copy", systemImage: "square.on.square") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(credential.token, forType: .string)
                    }
                    .controlSize(.small)
                    Button("Remove", systemImage: "trash", role: .destructive) {
                        profile.clientCredentials.removeAll { $0.id == credential.id }
                    }
                    .controlSize(.small)
                }
            }

            HStack {
                Button("Add key", systemImage: "plus") {
                    let number = profile.clientCredentials.count + 1
                    profile.clientCredentials.append(.generate(name: "AI \(number)"))
                }
                .controlSize(.small)

                if profile.clientCredentials.isEmpty {
                    Text("Add at least one key before starting a protected route.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private var leaseTitle: String {
        if let lease = model.lease(for: profile.id) {
            return "\(lease.clientName) is connected"
        }
        return profile.remoteClientCompatibilityEnabled ? "Ready for remote clients" : "Ready for client access"
    }

    private var leaseSymbol: String {
        model.lease(for: profile.id) != nil ? "checkmark.shield.fill" : "shield.checkered"
    }

    private var leaseColor: Color {
        model.lease(for: profile.id) != nil ? .green : .secondary
    }

    private var gatewayPortBinding: Binding<String> {
        Binding(
            get: { String(profile.gatewayPort) },
            set: { text in
                let digits = text.filter(\.isNumber)
                if let value = Int(digits), (1024...65535).contains(value) {
                    profile.gatewayPort = value
                }
            }
        )
    }
}
