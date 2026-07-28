import SwiftUI

struct TailscaleMark: View {
    let isActive: Bool

    private let opacity: [[Double]] = [
        [0.34, 1.0, 0.34],
        [1.0, 1.0, 1.0],
        [0.34, 1.0, 0.34]
    ]

    var body: some View {
        VStack(spacing: 1.7) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 1.7) {
                    ForEach(0..<3, id: \.self) { column in
                        Circle()
                            .fill(Color.primary.opacity(isActive ? opacity[row][column] : opacity[row][column] * 0.42))
                            .frame(width: 2.7, height: 2.7)
                    }
                }
            }
        }
        .frame(width: 16, height: 16)
        .contentShape(Rectangle())
        .accessibilityHidden(true)
    }
}

struct TailscaleToolbarButton: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Button {
            if model.tailscaleFunnelRunning { model.stopTailscaleFunnel() }
            else { model.startTailscaleFunnel() }
        } label: {
            TailscaleMark(isActive: model.tailscaleFunnelRunning)
        }
        .help(model.tailscaleFunnelRunning ? "Stop Tailscale Funnel" : "Start Tailscale Funnel")
        .accessibilityLabel(model.tailscaleFunnelRunning ? "Stop Tailscale Funnel" : "Start Tailscale Funnel")
        .animation(.easeInOut(duration: 0.18), value: model.tailscaleFunnelRunning)
    }
}
