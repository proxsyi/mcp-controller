import SwiftUI
import AppKit

struct GatewayAccessView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var profile: ServerProfile
    @State private var originText = ""

    var body: some View {
        ContentCard(title: "Exclusive AI access", symbol: "person.badge.key") {
            VStack(alignment: .leading, spacing: 16) {
                Toggle("Allow only one AI at a time", isOn: $profile.exclusiveGatewayEnabled)
                    .fontWeight(.medium)
                Text("MCP Controller sits between Tailscale and the local server. The first approved access key receives the lease; another AI gets a retryable connection-in-use response and appears here for approval.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if profile.exclusiveGatewayEnabled {
                    Divider()
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 14) {
                        GridRow {
                            Text("Gateway port").foregroundStyle(.secondary)
                            TextField("39000", value: $profile.gatewayPort, format: .number)
                                .frame(width: 110)
                        }
                        GridRow {
                            Text("Lease timeout").foregroundStyle(.secondary)
                            HStack {
                                Stepper("\(profile.leaseTimeoutSeconds / 60) min", value: $profile.leaseTimeoutSeconds, in: 60...86_400, step: 60)
                                    .labelsHidden()
                                Text("\(profile.leaseTimeoutSeconds / 60) minutes").monospacedDigit()
                            }
                        }
                        GridRow {
                            Text("Allowed origins").foregroundStyle(.secondary)
                            TextField("Optional, comma separated", text: $originText)
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    Text("Leave origins empty for non-browser clients that omit the Origin header. Any request that includes an Origin is rejected unless it exactly matches this list.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    credentials
                    leaseStatus
                }
            }
        }
        .onAppear { originText = profile.allowedOrigins.joined(separator: ", ") }
        .onChange(of: originText) { _, value in
            profile.allowedOrigins = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
    }

    private var credentials: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("AI access keys").font(.subheadline.weight(.semibold))
                Spacer()
                Button("Add Key", systemImage: "plus") {
                    let number = profile.clientCredentials.count + 1
                    profile.clientCredentials.append(.generate(name: "AI \(number)"))
                }
            }
            if profile.clientCredentials.isEmpty {
                Text("Add one unique key for each AI connection. The server cannot start in exclusive mode without a key.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            ForEach($profile.clientCredentials) { $credential in
                HStack(spacing: 10) {
                    TextField("AI name", text: $credential.name)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                    Text(credential.token)
                        .font(.system(.caption2, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    Spacer()
                    Button("Copy", systemImage: "doc.on.doc") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(credential.token, forType: .string)
                    }
                    .labelStyle(.iconOnly)
                    Button("Remove", systemImage: "trash", role: .destructive) {
                        profile.clientCredentials.removeAll { $0.id == credential.id }
                    }
                    .labelStyle(.iconOnly)
                }
            }
            Text("Use each key as the Bearer token for its AI's MCP connection. Gateway tokens are consumed locally and are not forwarded upstream.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var leaseStatus: some View {
        Divider()
        VStack(alignment: .leading, spacing: 10) {
            Text("Current access").font(.subheadline.weight(.semibold))
            if let lease = model.lease(for: profile.id) {
                HStack {
                    Label(lease.clientName, systemImage: "checkmark.shield.fill")
                        .foregroundStyle(.green)
                    Spacer()
                    Text("Active").font(.caption).foregroundStyle(.secondary)
                    Button("Release") { model.releaseLease(profileID: profile.id) }
                }
            } else {
                Label("No AI holds the lease", systemImage: "shield")
                    .foregroundStyle(.secondary)
            }

            let waiting = model.waiting(for: profile.id)
            if !waiting.isEmpty {
                Text("Waiting for confirmation").font(.subheadline.weight(.semibold)).padding(.top, 4)
                ForEach(waiting) { request in
                    HStack {
                        Label(request.clientName, systemImage: "person.crop.circle.badge.questionmark")
                        Spacer()
                        Button("Deny", role: .destructive) {
                            model.deny(profileID: profile.id, clientID: request.clientID)
                        }
                        Button("Approve") {
                            model.approve(profileID: profile.id, clientID: request.clientID)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
    }
}
