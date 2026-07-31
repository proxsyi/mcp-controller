import SwiftUI
import AppKit

struct TailscaleToolbarButton: View {
    var body: some View {
        Button {
            _ = NSApplication.shared.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } label: {
            Image(systemName: "globe")
                .font(.system(size: 13, weight: .semibold))
        }
        .buttonStyle(PerfectCircleToolbarButtonStyle())
        .help("Remote access settings")
    }
}
