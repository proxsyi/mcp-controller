import SwiftUI

struct TailscaleMark: View {
    let isActive: Bool
    let isAnimating: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let officialOpacity: [[Double]] = [
        [0.20, 0.20, 0.20],
        [1.00, 1.00, 1.00],
        [0.20, 1.00, 0.20]
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isAnimating || reduceMotion)) { timeline in
            GeometryReader { proxy in
                let side = min(proxy.size.width, proxy.size.height)
                let diameter = side * 0.25
                let elapsed = timeline.date.timeIntervalSinceReferenceDate

                ZStack(alignment: .topLeading) {
                    ForEach(0..<3, id: \.self) { row in
                        ForEach(0..<3, id: \.self) { column in
                            let index = row * 3 + column
                            let wave = (sin(elapsed * 9.5 - Double(index) * 0.72) + 1) / 2
                            let animatedScale = isAnimating && !reduceMotion ? 0.78 + wave * 0.28 : 1
                            let animatedOpacity = isAnimating && !reduceMotion ? 0.58 + wave * 0.42 : 1
                            let baseOpacity = officialOpacity[row][column]
                            let stateOpacity = isActive ? baseOpacity : max(0.10, baseOpacity * 0.43)

                            Circle()
                                .fill(Color.primary.opacity(stateOpacity * animatedOpacity))
                                .frame(width: diameter, height: diameter)
                                .scaleEffect(animatedScale)
                                .position(
                                    x: side * (0.125 + Double(column) * 0.375),
                                    y: side * (0.125 + Double(row) * 0.375)
                                )
                        }
                    }
                }
                .frame(width: side, height: side)
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(width: 22, height: 22)
        .scaleEffect(isAnimating && !reduceMotion ? 1.06 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.68), value: isAnimating)
        .contentShape(Rectangle())
        .accessibilityHidden(true)
    }
}

struct TailscaleToolbarButton: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAnimating = false

    var body: some View {
        Button {
            guard !isAnimating else { return }
            Task { @MainActor in
                isAnimating = true
                if !reduceMotion { try? await Task.sleep(for: .milliseconds(260)) }
                if model.tailscaleFunnelRunning { model.stopTailscaleFunnel() }
                else { model.startTailscaleFunnel() }
                if !reduceMotion { try? await Task.sleep(for: .milliseconds(460)) }
                isAnimating = false
            }
        } label: {
            TailscaleMark(isActive: model.tailscaleFunnelRunning, isAnimating: isAnimating)
        }
        .buttonStyle(PerfectCircleToolbarButtonStyle())
        .disabled(isAnimating)
        .help(model.tailscaleFunnelRunning ? "Stop Tailscale Funnel" : "Start Tailscale Funnel")
        .accessibilityLabel(model.tailscaleFunnelRunning ? "Stop Tailscale Funnel" : "Start Tailscale Funnel")
        .animation(.easeInOut(duration: 0.2), value: model.tailscaleFunnelRunning)
    }
}
