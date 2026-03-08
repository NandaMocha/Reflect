import SwiftUI

struct ConfettiView: View {
    @State private var isAnimating = false

    let duration: Double = 3.0
    let particleCount = 50

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Confetti particles
                ForEach(0..<particleCount, id: \.self) { index in
                    ConfettiParticle(
                        index: index,
                        total: particleCount,
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

private struct ConfettiParticle: View {
    let index: Int
    let total: Int
    let size: CGSize
    let isAnimating: Bool

    // Random properties for variety
    private var color: Color {
        let colors: [Color] = [
            .red, .blue, .green, .yellow, .orange, .purple, .pink, .cyan
        ]
        return colors.randomElement() ?? .confetti
    }

    private var rotation: Double {
        Double.random(in: 0...360)
    }

    private var endY: CGFloat {
        size.height + 50
    }

    private var duration: Double {
        Double.random(in: 2...3)
    }

    private var delay: Double {
        Double.random(in: 0...0.5)
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(color)
            .frame(width: 8, height: 8)
            .rotationEffect(.degrees(rotation))
            .offset(
                x: CGFloat.random(in: 0...size.width),
                y: isAnimating ? endY : -50
            )
            .opacity(isAnimating ? 0 : 1)
            .animation(
                .easeOut(duration: duration)
                    .delay(delay),
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
