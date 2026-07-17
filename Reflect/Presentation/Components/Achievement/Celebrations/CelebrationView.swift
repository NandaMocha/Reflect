import SwiftUI

/// Full-screen celebration shown after a badge unlocks. Deliberately minimal —
/// small overline, large icon, badge name as the hero, one line of description,
/// and a "Next up" teaser pointing at the next milestone in the same category.
/// Confetti + haptic carry the celebration energy.
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
                Spacer()

                VStack(spacing: 24) {
                    Text("Achievement Unlocked")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(1.5)

                    badgeIcon

                    VStack(spacing: 8) {
                        Text(badgeID.displayName)
                            .font(.largeTitle.bold())
                            .multilineTextAlignment(.center)

                        Text(badgeID.badgeDescription)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    if let next = badgeID.nextInCategory {
                        NextUpCard(next: next, justUnlocked: badgeID)
                            .padding(.top, 8)
                    }
                }
                .padding(.horizontal, 24)

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

// MARK: - Next Up Card

private struct NextUpCard: View {
    let next: BadgeID
    let justUnlocked: BadgeID

    private var more: Int {
        max(next.requiredCount - justUnlocked.requiredCount, 0)
    }

    private var subtext: String {
        let unit: String
        switch next.badgeCategory {
        case .reflections: unit = more == 1 ? "reflection" : "reflections"
        case .media: unit = more == 1 ? "more with media" : "more reflections with media"
        case .prompts: unit = more == 1 ? "more with a prompt" : "more reflections with a prompt"
        case .special: unit = more == 1 ? "reflection" : "reflections"
        }
        return "\(more) more \(unit) to go"
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color(.tertiarySystemFill))
                    .frame(width: 44, height: 44)
                Image(systemName: next.icon)
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("NEXT UP")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.tertiary)
                    .tracking(1.0)
                Text(next.displayName)
                    .font(.headline)
                Text(subtext)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview("First Step") {
    CelebrationView(badgeID: .firstReflection)
}

#Preview("Last milestone (no next-up)") {
    CelebrationView(badgeID: .thousandReflections)
}
