import SwiftUI

struct PerfectCircleToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(.iconOnly)
            .frame(width: 32, height: 32, alignment: .center)
            .background {
                Circle()
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.17 : 0.085))
                    .frame(width: 32, height: 32)
            }
            .overlay {
                Circle()
                    .strokeBorder(Color.primary.opacity(configuration.isPressed ? 0.22 : 0.11), lineWidth: 0.75)
                    .frame(width: 32, height: 32)
            }
            .clipShape(Circle())
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.72), value: configuration.isPressed)
    }
}
