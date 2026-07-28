import SwiftUI

struct ConfettiView: View {
    @State private var isAnimating = false

    let duration: Double = 3.0
    let particleCount = 50

    // Each particle's randomised properties are generated ONCE when the view's state is
    // created, not on every `body` evaluation. Re-rolling in `body` (the old behaviour) let a
    // particle's colour, rotation, and horizontal position jump/recolour mid-celebration.
    @State private var specs: [ParticleSpec] = (0..<50).map { _ in ParticleSpec.random() }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(specs.indices, id: \.self) { index in
                    ConfettiParticle(
                        spec: specs[index],
                        size: geometry.size,
                        isAnimating: isAnimating
                    )
                }
            }
            .onAppear {
                withAnimation(.easeOut(duration: duration)) {
                    isAnimating = true
                }
            }
        }
    }
}

/// Stable, pre-computed properties for a single confetti particle. `xFraction` is stored as a
/// 0...1 fraction so the horizontal position can be resolved against the runtime geometry width
/// without re-randomising.
private struct ParticleSpec {
    let color: Color
    let rotation: Double
    let duration: Double
    let delay: Double
    let xFraction: CGFloat

    static func random() -> ParticleSpec {
        let colors: [Color] = [
            .red, .blue, .green, .yellow, .orange, .purple, .pink, .cyan
        ]
        return ParticleSpec(
            color: colors.randomElement() ?? .confetti,
            rotation: .random(in: 0...360),
            duration: .random(in: 2...3),
            delay: .random(in: 0...0.5),
            xFraction: .random(in: 0...1)
        )
    }
}

private struct ConfettiParticle: View {
    let spec: ParticleSpec
    let size: CGSize
    let isAnimating: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(spec.color)
            .frame(width: 8, height: 8)
            .rotationEffect(.degrees(spec.rotation))
            .offset(
                x: spec.xFraction * size.width,
                y: isAnimating ? size.height + 50 : -50
            )
            .opacity(isAnimating ? 0 : 1)
            .animation(
                .easeOut(duration: spec.duration)
                    .delay(spec.delay),
                value: isAnimating
            )
    }
}

extension Color {
    static let confetti = Color(red: 1.0, green: 0.8, blue: 0.2)
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack {
            Text("🎉 Confetti Celebration!")
                .font(.title)
                .foregroundStyle(.white)
                .padding()
        }

        ConfettiView()
    }
}
