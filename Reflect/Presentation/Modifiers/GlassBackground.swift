import SwiftUI

struct GlassBackground: ViewModifier {
    let cornerRadius: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.ultraThinMaterial)
                    .opacity(opacity)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.3),
                                .white.opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            }
            .shadow(
                color: .black.opacity(0.08),
                radius: 8,
                x: 0,
                y: 4
            )
    }
}

extension View {
    func glassBackground(
        cornerRadius: CGFloat = Constants.CornerRadius.large,
        opacity: Double = 1.0
    ) -> some View {
        modifier(GlassBackground(cornerRadius: cornerRadius, opacity: opacity))
    }
}

// MARK: - Glass Card Style

struct GlassCard: ViewModifier {
    @Environment(\.colorScheme) var colorScheme

    func body(content: Content) -> some View {
        content
            .padding(Constants.Spacing.md)
            .background {
                RoundedRectangle(cornerRadius: Constants.CornerRadius.large)
                    .fill(colorScheme == .dark ? Color.backgroundSecondaryDark : Color.backgroundSecondaryLight)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Constants.CornerRadius.large)
                    .stroke(
                        LinearGradient(
                            colors: [
                                .white.opacity(colorScheme == .dark ? 0.1 : 0.3),
                                .white.opacity(colorScheme == .dark ? 0.05 : 0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            }
            .shadow(
                color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08),
                radius: 8,
                x: 0,
                y: 4
            )
    }
}

extension View {
    func glassCard() -> some View {
        modifier(GlassCard())
    }
}
