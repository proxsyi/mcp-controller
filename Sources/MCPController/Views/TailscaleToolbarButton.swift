import SwiftUI

struct TailscaleToolbarButton: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button {
            openSettings()
        } label: {
            Image(systemName: "globe")
                .font(.system(size: 13, weight: .semibold))
        }
        .buttonStyle(PerfectCircleToolbarButtonStyle())
        .help("Remote access settings")
    }
}
