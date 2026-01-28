import SwiftUI

struct CardStyle: ViewModifier {
    @Environment(\.colorScheme) var colorScheme

    let padding: CGFloat
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .shadow(
                color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08),
                radius: 8,
                x: 0,
                y: 4
            )
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(colorScheme == .dark ? Color.backgroundSecondaryDark : Color.backgroundSecondaryLight)
    }
}

extension View {
    func cardStyle(
        padding: CGFloat = Constants.Spacing.md,
        cornerRadius: CGFloat = Constants.CornerRadius.large
    ) -> some View {
        modifier(CardStyle(padding: padding, cornerRadius: cornerRadius))
    }
}

// MARK: - Pressable Card Style

struct PressableCardStyle: ButtonStyle {
    @Environment(\.colorScheme) var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableCardStyle {
    static var pressableCard: PressableCardStyle {
        PressableCardStyle()
    }
}
