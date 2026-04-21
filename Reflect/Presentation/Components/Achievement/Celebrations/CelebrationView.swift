import SwiftUI

/// Full-screen celebration shown after a badge unlocks. Deliberately minimal —
/// small overline, large icon, badge name as the hero, one line of description,
/// and a Continue button. The confetti + haptic carry the celebration energy;
/// the layout stays out of their way.
struct CelebrationView: View {
    let badgeID: BadgeID
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            ConfettiView()
                .allowsHitTesting(false)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 24)

                Text("Achievement Unlocked")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(1.5)

                Spacer(minLength: 24)

                badgeIcon

                Spacer(minLength: 24)

                VStack(spacing: 12) {
                    Text(badgeID.displayName)
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)

                    Text(badgeID.badgeDescription)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

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
                .frame(width: 160, height: 160)

            Image(systemName: badgeID.icon)
                .font(.system(size: 72))
                .foregroundStyle(Color.blue)
        }
        .shadow(color: Color.blue.opacity(0.3), radius: 16)
    }
}

#Preview {
    CelebrationView(badgeID: .firstReflection)
}
