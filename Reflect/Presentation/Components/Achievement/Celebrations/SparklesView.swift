import SwiftUI

struct SparklesView: View {
    @State private var isAnimating = false

    let duration: Double = 3.5
    let sparkleCount = 40

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Sparkle particles
                ForEach(0..<sparkleCount, id: \.self) { index in
                    SparkleParticle(
                        index: index,
                        total: sparkleCount,
                        size: geometry.size,
                        isAnimating: isAnimating
                    )
                }
            }
            .onAppear {
                withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
                    isAnimating = true
                }
            }
        }
    }
}

private struct SparkleParticle: View {
    let index: Int
    let total: Int
    let size: CGSize
    let isAnimating: Bool

    private var position: CGPoint {
        CGPoint(
            x: CGFloat.random(in: 0...size.width),
            y: CGFloat.random(in: 0...size.height)
        )
    }

    private var scale: CGFloat {
        CGFloat.random(in: 0.5...1.5)
    }

    private var rotation: Angle {
        .degrees(Double.random(in: 0...360))
    }

    private var duration: Double {
        Double.random(in: 1...2)
    }

    private var delay: Double {
        Double.random(in: 0...1)
    }

    var body: some View {
        Image(systemName: "sparkle")
            .font(.system(size: 20))
            .foregroundStyle(sparkleColors.randomElement() ?? .yellow)
            .scaleEffect(isAnimating ? scale : 0)
            .rotationEffect(isAnimating ? rotation : .zero)
            .position(position)
            .opacity(isAnimating ? 0 : 1)
            .animation(
                .easeOut(duration: duration)
                    .delay(delay),
                value: isAnimating
            )
    }
}

private var sparkleColors: [Color] = [
    .yellow, .orange, .white, .cyan, .pink
]

#Preview {
    ZStack {
        Color.blue.ignoresSafeArea()

        VStack {
            Text("✨ Sparkles Celebration!")
                .font(.title)
                .foregroundStyle(.white)
                .padding()
        }

        SparklesView()
    }
}
