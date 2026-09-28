import SwiftUI
import SwiftData
import CloudKit

enum MainTab {
    case learnings
    case insights
    case spaces
}

struct MainTabView: View {
    @State private var showOnboarding: Bool = false
    /// Celebration presentation lives here at the app root so it survives the editor's
    /// dismissal. When `.badgesDidUnlock` fires — posted by CreateReflectionUseCase /
    /// UpdateReflectionUseCase after a save — we stash the headline badge and let
    /// `.fullScreenCover` take over. The editor's own dismiss runs independently.
    @State private var celebrationBadgeID: BadgeID?
    @Environment(\.modelContext) private var modelContext

    // Widget action binding
    @Binding var widgetAction: WidgetAction?

    @State private var selectedTab: MainTab = .learnings
    @State private var insightComposeSignal = false

    // Space invite acceptance — queued until any onboarding sheet / celebration cover is
    // down, so accepting doesn't fight the presentation stack. `pendingOpenSpace` deep-links
    // the Spaces list into the joined space once accepted.
    @State private var pendingInviteMetadata: CKShare.Metadata?
    @State private var pendingOpenSpace: Space?
    @State private var isAcceptingInvite = false
    @State private var inviteErrorMessage: String?

    // Guest-feedback request link ("/f/<token>", AC-014) — same queue-until-settled
    // pattern as the invite state above, kept as its own set of state since resolving a
    // token can land on an *existing* thread rather than a freshly-accepted space.
    @State private var pendingRequestToken: String?
    @State private var pendingOpenThread: SpaceThreadDeepLink?
    @State private var isResolvingRequestLink = false
    @State private var requestLinkErrorMessage: String?

    init(widgetAction: Binding<WidgetAction?> = .constant(nil)) {
        self._widgetAction = widgetAction
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Chapters", systemImage: "book.fill", value: .learnings) {
                LearningListView(widgetAction: $widgetAction)
            }

            Tab("Insights", systemImage: "lightbulb.fill", value: .insights) {
                InsightListView(composeSignal: $insightComposeSignal)
                    .modelContainer(InsightStore.container)
                    .accessibilityIdentifier("insights.tab")
            }

            Tab("Spaces", systemImage: "person.3.fill", value: .spaces) {
                // No .modelContainer: Space views get their data through ViewModels, not @Query.
                SpaceListView(openSpace: $pendingOpenSpace, openThread: $pendingOpenThread)
            }
        }
        .onAppear {
            checkOnboardingStatus()
            // Cold-launch / raced-notification invites are stashed in the inbox; pick them up.
            drainInviteInboxIfPossible()
            drainRequestLinkInboxIfPossible()
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView(isPresented: $showOnboarding)
        }
        .fullScreenCover(item: $celebrationBadgeID) { badgeID in
            CelebrationView(badgeID: badgeID)
        }
        .onReceive(NotificationCenter.default.publisher(for: .badgesDidUnlock)) { notification in
            guard let badgeIDs = notification.object as? [BadgeID],
                  let headline = BadgeID.headline(from: badgeIDs) else { return }
            celebrationBadgeID = headline
        }
        .onChange(of: widgetAction) { _, action in
            guard let action else { return }
            if action == .insight {
                selectedTab = .insights
                insightComposeSignal = true
                widgetAction = nil
            } else {
                // Write/Camera/Voice are handled by LearningListView, which clears
                // widgetAction itself once it's done — just make sure that tab is
                // the one on screen so the user doesn't land back on Insights.
                selectedTab = .learnings
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .spaceShareInviteReceived)) { _ in
            drainInviteInboxIfPossible()
        }
        .onReceive(NotificationCenter.default.publisher(for: .spaceRequestLinkReceived)) { _ in
            drainRequestLinkInboxIfPossible()
        }
        .onChange(of: showOnboarding) { _, isShowing in
            if !isShowing {
                processPendingInviteIfPossible()
                processPendingRequestLinkIfPossible()
            }
        }
        .onChange(of: celebrationBadgeID) { _, badge in
            if badge == nil {
                processPendingInviteIfPossible()
                processPendingRequestLinkIfPossible()
            }
        }
        .errorAlert($inviteErrorMessage, title: "Couldn't Join Space")
        .errorAlert($requestLinkErrorMessage, title: "Couldn't Open Link")
    }

    private func checkOnboardingStatus() {
#if DEBUG
        // Developer override (Settings → Debug → "Always show onboarding"): re-present the
        // first-run sheet on every launch so it can be reviewed without deleting the app.
        // Compiled out of release builds entirely.
        if UserDefaults.standard.bool(forKey: Constants.UserDefaults.debugAlwaysShowOnboarding) {
            showOnboarding = true
            return
        }
#endif
        let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: Constants.UserDefaults.hasCompletedOnboarding)
        if !hasCompletedOnboarding {
            showOnboarding = true
        }
    }

    /// Pulls any invite the scene/app delegate stashed (cold launch, or a notification that
    /// beat this view's subscription) into the pending slot and tries to process it.
    private func drainInviteInboxIfPossible() {
        if let metadata = SpaceInviteInbox.drain() {
            pendingInviteMetadata = metadata
        }
        processPendingInviteIfPossible()
    }

    /// Accepts a queued Space invite once no onboarding sheet or celebration cover is up,
    /// then switches to the Spaces tab and deep-links into the joined space. Queuing (rather
    /// than accepting inline in `onReceive`) avoids fighting the presentation stack when an
    /// invite arrives mid-onboarding or mid-celebration.
    private func processPendingInviteIfPossible() {
        guard let metadata = pendingInviteMetadata,
              !showOnboarding,
              celebrationBadgeID == nil,
              !isAcceptingInvite else { return }

        isAcceptingInvite = true
        pendingInviteMetadata = nil   // consume; a newer invite may re-populate this during the await
        selectedTab = .spaces

        Task {
            do {
                let space = try await DIContainer.shared.makeAcceptSpaceInviteUseCase().execute(metadata: metadata)
                pendingOpenSpace = space
            } catch {
                // Surface the failure instead of swallowing it; the user can re-tap the
                // invite link (the warm-accept path) to retry.
                inviteErrorMessage = error.localizedDescription
            }
            isAcceptingInvite = false
            // Drain a newer invite that arrived while this one was in flight.
            processPendingInviteIfPossible()
        }
    }

    // MARK: - Guest-feedback request links (AC-014)

    /// Pulls any `/f/<token>` open the delegate stashed (cold launch, or a notification
    /// that beat this view's subscription) into the pending slot and tries to resolve it.
    private func drainRequestLinkInboxIfPossible() {
        if let token = SpaceInviteInbox.drainRequestToken() {
            pendingRequestToken = token
        }
        processPendingRequestLinkIfPossible()
    }

    /// Resolves a queued request-link token once no onboarding sheet or celebration cover
    /// is up, then switches to the Spaces tab and deep-links straight into that request's
    /// thread — accepting the underlying Space invite first if this device isn't already a
    /// member (`ResolveRequestLinkUseCase` handles both cases).
    private func processPendingRequestLinkIfPossible() {
        guard let token = pendingRequestToken,
              !showOnboarding,
              celebrationBadgeID == nil,
              !isResolvingRequestLink else { return }

        isResolvingRequestLink = true
        pendingRequestToken = nil   // consume; a newer link may re-populate this during the await
        selectedTab = .spaces

        Task {
            do {
                let deepLink = try await DIContainer.shared.makeResolveRequestLinkUseCase().execute(token: token)
                pendingOpenThread = deepLink
            } catch {
                // Surface the failure instead of swallowing it — an unknown/revoked token
                // is expected to end here with a friendly message (AC-014's acceptance).
                requestLinkErrorMessage = error.localizedDescription
            }
            isResolvingRequestLink = false
            // Drain a newer link that arrived while this one was in flight.
            processPendingRequestLinkIfPossible()
        }
    }
}

#Preview {
    @Previewable @State var action: WidgetAction? = nil
    MainTabView(widgetAction: $action)
        .modelContainer(for: [Learning.self, Reflection.self, ImageAttachment.self, VoiceRecording.self, VideoAttachment.self], inMemory: true)
}
