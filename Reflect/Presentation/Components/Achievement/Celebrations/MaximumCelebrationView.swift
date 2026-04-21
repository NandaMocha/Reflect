import SwiftUI

struct MaximumCelebrationView: View {
    @State private var showConfetti = false
    @State private var showSparkles = false
    @State private var showFireworks = false

    let duration: Double = 5.0

    var body: some View {
        ZStack {
            // Layer 1: Sparkles (background)
            if showSparkles {
                SparklesView()
                    .opacity(0.6)
            }

            // Layer 2: Fireworks (middle)
            if showFireworks {
                FireworksView()
            }

            // Layer 3: Confetti (foreground)
            if showConfetti {
                ConfettiView()
            }

            // Celebration message
            VStack {
                Spacer()

                VStack(spacing: 16) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(.yellow)
                        .shadow(color: .orange, radius: 20)

                    Text("🎉 ACHIEVEMENT UNLOCKED! 🎉")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .shadow(radius: 10)

                    Text("Incredible dedication!")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.9))
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.ultraThinMaterial)
                        .padding()
                )

                Spacer()
            }
        }
        .onAppear {
            // Stagger the animations for maximum impact
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                showSparkles = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showFireworks = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                showConfetti = true
            }
        }
    }
}

#Preview {
    ZStack {
        LinearGradient(
            colors: [.purple, .blue],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()

        MaximumCelebrationView()
    }
}
