import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.profiles.isEmpty {
                Text("No MCP servers configured")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.profiles) { profile in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(profile.name)
                            Text(model.phase(for: profile.id).title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if model.phase(for: profile.id).isActive {
                            Button("Stop") { model.stop(profile) }
                        } else {
                            Button("Start") { model.start(profile) }
                        }
                    }
                }
                Divider()
                Button("Stop everything", role: .destructive) { model.stopAll() }
                    .disabled(model.runningCount == 0)
            }
        }
        .padding(12)
        .frame(width: 320)
    }
}
