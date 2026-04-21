import SwiftUI

// Import Foundation for math functions
import Foundation

struct FireworksView: View {
    @State private var isAnimating = false
    @State private var explosionPhase = 0.0

    let duration: Double = 4.0
    let rocketCount = 5

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Firework rockets
                ForEach(0..<rocketCount, id: \.self) { index in
                    FireworkRocket(
                        index: index,
                        total: rocketCount,
                        size: geometry.size,
                        isAnimating: isAnimating,
                        phase: explosionPhase
                    )
                }
            }
            .onAppear {
                // Trigger explosion animation
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation(.easeOut(duration: 1.5)) {
                        explosionPhase = 1.0
                    }
                }
            }
        }
        .onChange(of: explosionPhase) { _, _ in
            if explosionPhase >= 1.0 {
                isAnimating = true
            }
        }
    }
}

private struct FireworkRocket: View {
    let index: Int
    let total: Int
    let size: CGSize
    let isAnimating: Bool
    let phase: Double

    private var startPosition: CGPoint {
        CGPoint(
            x: CGFloat.random(in: size.width * 0.2...size.width * 0.8),
            y: size.height
        )
    }

    private var endPosition: CGPoint {
        CGPoint(
            x: CGFloat.random(in: size.width * 0.3...size.width * 0.7),
            y: size.height * 0.3
        )
    }

    private var particleCount: Int {
        Int.random(in: 20...40)
    }

    private var color: Color {
        let colors: [Color] = [
            .red, .orange, .yellow, .green, .blue, .purple, .pink
        ]
        return colors.randomElement() ?? .orange
    }

    var body: some View {
        ZStack {
            // Rocket trail
            if phase < 1.0 {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                    .position(isAnimating ? endPosition : startPosition)
                    .opacity(isAnimating ? 0 : 1)
                    .animation(.easeOut(duration: 0.8), value: isAnimating)
            }

            // Explosion particles
            if phase >= 0.8 {
                ForEach(0..<particleCount, id: \.self) { particleIndex in
                    ExplosionParticle(
                        origin: endPosition,
                        color: color,
                        index: particleIndex,
                        isExploding: phase >= 0.8
                    )
                }
            }
        }
    }
}

private struct ExplosionParticle: View {
    let origin: CGPoint
    let color: Color
    let index: Int
    let isExploding: Bool

    private var angle: Angle {
        let degrees = Double(index) * (360.0 / 40.0)
        return .degrees(degrees)
    }

    private var distance: CGFloat {
        CGFloat.random(in: 50...150)
    }

    private var endPosition: CGPoint {
        let radians = angle.radians
        return CGPoint(
            x: origin.x + Foundation.cos(radians) * distance,
            y: origin.y + Foundation.sin(radians) * distance
        )
    }

    private var size: CGFloat {
        CGFloat.random(in: 4...12)
    }

    private var duration: Double {
        Double.random(in: 0.5...1.0)
    }

    private var delay: Double {
        Double.random(in: 0...0.2)
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .position(isExploding ? endPosition : origin)
            .opacity(isExploding ? 0 : 1)
            .animation(
                .easeOut(duration: duration)
                    .delay(delay),
                value: isExploding
            )
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack {
            Text("🎆 Fireworks Celebration!")
                .font(.title)
                .foregroundStyle(.white)
                .padding()
        }

        FireworksView()
    }
}
