import SwiftUI

/// Persisted acknowledgment that the user accepted the Spaces content terms. Namespaced
/// key (`space…`) kept out of the lock-restricted `Constants.swift`.
enum SpaceTerms {
    private static let acceptedKey = "spaceHasAcceptedTerms"

    static var hasAccepted: Bool {
        get { UserDefaults.standard.bool(forKey: acceptedKey) }
        set { UserDefaults.standard.set(newValue, forKey: acceptedKey) }
    }
}

/// One-time acknowledgment shown before first Spaces use. Apple requires apps with
/// user-generated content to state a no-tolerance policy for objectionable content and
/// give users a way to report it and block/leave (plan §10). This is the acknowledgment
/// half; `ReportContentButton`, owner-delete, and leave/remove are the mechanisms.
struct SpaceTermsSheet: View {
    /// Called when the user accepts (after this sheet has already set `SpaceTerms.hasAccepted`).
    let onAccept: () -> Void

    var body: some View {
        VStack(spacing: Constants.Spacing.lg) {
            Spacer(minLength: Constants.Spacing.xl)

            Image(systemName: "person.3.sequence.fill")
                .font(.system(size: 52))
                .foregroundStyle(Color.primaryDefault)

            Text("Before you join Spaces")
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: Constants.Spacing.md) {
                policyRow(
                    icon: "hand.raised.fill",
                    title: "Be respectful",
                    detail: "Spaces are shared with people you invite. There's no tolerance for objectionable, abusive, or harmful content."
                )
                policyRow(
                    icon: "exclamationmark.bubble.fill",
                    title: "Report anything off",
                    detail: "Every feedback request and piece of feedback has a Report action that emails us the details so we can act on it."
                )
                policyRow(
                    icon: "rectangle.portrait.and.arrow.right.fill",
                    title: "You're in control",
                    detail: "Owners can remove members or delete a space for everyone; members can leave at any time."
                )
            }
            .padding(.horizontal, Constants.Spacing.md)

            Spacer()

            PrimaryButton("I Understand", icon: "checkmark") {
                SpaceTerms.hasAccepted = true
                onAccept()
            }
            .padding(.horizontal, Constants.Spacing.md)
            .padding(.bottom, Constants.Spacing.md)
        }
        .padding(Constants.Spacing.md)
        .interactiveDismissDisabled()
    }

    private func policyRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: Constants.Spacing.sm) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.primaryDefault)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    SpaceTermsSheet(onAccept: {})
}
