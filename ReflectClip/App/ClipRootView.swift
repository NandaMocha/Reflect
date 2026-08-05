import SwiftUI

/// Root view for the Clip — switches on `ClipSession.phase`. `.needsName` is real
/// (`GuestNamePrompt`, `Features/Identity/GuestNamePrompt.swift`); the remaining phases are still
/// lightweight placeholders that fill in with real composer/all-feedback screens across later
/// tickets (AC-031/032). Uses only system semantic colors —
/// `Reflect/Core/Extensions/Color+Hex.swift` isn't shared into this target yet (see
/// `Reflect/ClipShared/README.md`).
///
/// The `.loading` → `.invocationTimedOut` timeout is owned by `ClipSession`
/// (`startResolutionTimeout()`, started from `ReflectClipApp`) rather than this view, so it's
/// testable independent of view appearance and survives the view being recreated.
struct ClipRootView: View {
    let session: ClipSession

    var body: some View {
        Group {
            switch session.phase {
            case .loading:
                ProgressView()
                    .controlSize(.large)
            case .needsName:
                GuestNamePrompt(session: session)
            case .compose:
                PhasePlaceholderView(
                    systemImage: "square.and.pencil",
                    title: "Ready to respond",
                    message: composeGreeting
                )
            case .allFeedback:
                PhasePlaceholderView(
                    systemImage: "bubble.left.and.bubble.right",
                    title: "Everyone's answers",
                    message: "The shared feed lands in a later ticket."
                )
            case .invocationTimedOut:
                InvocationTimedOutPlaceholderView(session: session)
            case .invalidLink:
                PhasePlaceholderView(
                    systemImage: "link.badge.plus",
                    title: "This link isn't working",
                    message: "Ask for a fresh invite — this one may have expired or been revoked."
                )
            }
        }
        .animation(.default, value: session.phase)
    }

    private var composeGreeting: String {
        guard let name = session.guestIdentity?.displayName, !name.isEmpty else {
            return "The composer lands in a later ticket."
        }
        return "Hi \(name) — the composer lands in a later ticket."
    }
}

/// Shown when `.loading` timed out with no invocation delivered by either path (see
/// `ClipSession.startResolutionTimeout()`). Deliberately distinct from `.invalidLink`: this is
/// "we haven't heard back yet," not "this link is bad" — neutral copy plus a retry affordance,
/// since a genuinely bad/revoked token is a different guest-facing situation.
private struct InvocationTimedOutPlaceholderView: View {
    let session: ClipSession
    @ScaledMetric(relativeTo: .title) private var iconSize: CGFloat = 40

    var body: some View {
        VStack(spacing: Constants.Spacing.lg) {
            VStack(spacing: Constants.Spacing.sm) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: iconSize))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text("Still connecting")
                    .font(.title2.bold())
                Text("This is taking longer than expected. You can try again.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button("Try Again") {
                session.retryResolution()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(Constants.Spacing.lg)
    }
}

private struct PhasePlaceholderView: View {
    let systemImage: String
    let title: String
    let message: String
    @ScaledMetric(relativeTo: .title) private var iconSize: CGFloat = 40

    var body: some View {
        VStack(spacing: Constants.Spacing.sm) {
            Image(systemName: systemImage)
                .font(.system(size: iconSize))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(title)
                .font(.title2.bold())
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(Constants.Spacing.lg)
    }
}
