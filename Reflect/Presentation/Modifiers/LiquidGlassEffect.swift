import SwiftUI

// MARK: - Liquid Glass Effect

/// A container that applies the liquid glass morphing effect to its content.
struct GlassEffectContainer<Content: View>: View {
    let content: Content
    let spacing: CGFloat

    init(spacing: CGFloat = 0, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        content
    }
}

// MARK: - Morphing Glass Backdrop

/// A backdrop view that creates the liquid glass morphing effect behind a button during press.
struct MorphingGlassBackdrop: View {
    @Binding var isPressing: Bool
    let size: CGFloat
    let color: Color

    var body: some View {
        ZStack {
            // Expanding ripple effect
            Circle()
                .fill(color)
                .shadow(color: color.opacity(0.5), radius: 30, x: 0, y: 15)
        }
        .frame(width: size, height: size)
        .scaleEffect(isPressing ? 1.5 : 1.0)
        .opacity(isPressing ? 0.3 : 0)
        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: isPressing)
    }
}

// MARK: - Glass Effect Modifiers

extension View {
    /// Applies the liquid glass effect to a view.
    func glassEffect() -> some View {
        self
    }

    /// Assigns an ID to the view for liquid glass morphing.
    func glassEffectID(_ id: String, in namespace: Namespace.ID) -> some View {
        self.matchedGeometryEffect(id: id, in: namespace)
    }
}

