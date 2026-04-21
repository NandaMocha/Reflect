import SwiftUI

/// Single full-screen celebration view shown after a badge unlocks. Replaces the earlier
/// variant-per-tier (Confetti/Sparkles/Fireworks/Maximum) approach — one layout,
/// confetti always, haptic rhythm plays on appear, user dismisses explicitly.
struct CelebrationView: View {
    let badgeID: BadgeID
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            // Background
            Color(.systemBackground)
                .ignoresSafeArea()

            // Confetti layer — sits behind content so the tap target is the dismiss button.
            ConfettiView()
                .allowsHitTesting(false)
                .ignoresSafeArea()

            // Content
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 8) {
                        Text("New Achievement Unlocked!")
                            .font(.title.bold())
                            .multilineTextAlignment(.center)

                        Text("You did it great! Keep going!")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 24)

                    badgeIcon

                    VStack(spacing: 8) {
                        Text(badgeID.displayName)
                            .font(.title2.bold())
                            .multilineTextAlignment(.center)

                        Text(badgeID.badgeDescription)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    HowToAchieveCard(badgeID: badgeID)

                    Spacer(minLength: 16)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity)
            }

            VStack {
                Spacer()
                PrimaryButton("Continue", icon: "checkmark") {
                    dismiss()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .onAppear {
            Task { await HapticManager.shared.playAchievementRhythm() }
        }
    }

    private var badgeIcon: some View {
        ZStack {
            Circle()
                .fill(Color.blue.opacity(0.15))
                .frame(width: 140, height: 140)

            Image(systemName: badgeID.icon)
                .font(.system(size: 60))
                .foregroundStyle(Color.blue)
        }
        .shadow(color: Color.blue.opacity(0.3), radius: 12)
    }
}

#Preview {
    CelebrationView(badgeID: .fiveReflections)
}
