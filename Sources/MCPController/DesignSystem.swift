import SwiftUI

enum GlassRole {
    case regular
    case clear
}

enum AppMotion {
    static func standard(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.82)
    }

    static func quick(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.86)
    }
}

extension View {
    @ViewBuilder
    func liquidGlass(
        _ role: GlassRole = .regular,
        cornerRadius: CGFloat = 20,
        interactive: Bool = false
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            switch role {
            case .regular:
                self.glassEffect(.regular.interactive(interactive), in: shape)
            case .clear:
                self
                    .background(Color.black.opacity(0.055), in: shape)
                    .glassEffect(.clear.interactive(interactive), in: shape)
            }
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.75))
        }
    }
}

struct ContentCard<Content: View>: View {
    let title: String
    let symbol: String
    let content: Content

    init(title: String, symbol: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.symbol = symbol
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .foregroundStyle(.primary)
            content
        }
        .padding(20)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.075), lineWidth: 0.75)
        }
    }
}

struct StatusPill: View {
    let phase: RuntimePhase

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(phase.title)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .liquidGlass(.clear, cornerRadius: 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Server status: \(phase.title)")
    }

    private var color: Color {
        switch phase {
        case .running: .green
        case .starting, .stopping: .orange
        case .failed: .red
        case .stopped: .secondary
        }
    }
}
