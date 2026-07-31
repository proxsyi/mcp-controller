import SwiftUI

struct TailscaleToolbarButton: View {
    @Environment(\.openSettings) private var openSettings
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Button {
            settings.preferredSettingsSection = "remoteAccess"
            openSettings()
        } label: {
            Image(systemName: "globe")
                .font(.system(size: 13, weight: .semibold))
        }
        .buttonStyle(PerfectCircleToolbarButtonStyle())
        .help("Remote access settings")
    }
}
