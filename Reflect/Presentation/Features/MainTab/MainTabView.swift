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

    init(widgetAction: Binding<WidgetAction?> = .constant(nil)) {
        self._widgetAction = widgetAction
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Learnings", systemImage: "book.fill", value: .learnings) {
                LearningListView(widgetAction: $widgetAction)
            }

            Tab("Insights", systemImage: "lightbulb.fill", value: .insights) {
                InsightListView(composeSignal: $insightComposeSignal)
                    .modelContainer(InsightStore.container)
            }

            Tab("Spaces", systemImage: "person.3.fill", value: .spaces) {
                // No .modelContainer: Space views get their data through ViewModels, not @Query.
                SpaceListView(openSpace: $pendingOpenSpace)
            }
        }
        .onAppear {
            checkOnboardingStatus()
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
        .onReceive(NotificationCenter.default.publisher(for: .spaceShareInviteReceived)) { notification in
            guard let metadata = notification.object as? CKShare.Metadata else { return }
            pendingInviteMetadata = metadata
            processPendingInviteIfPossible()
        }
        .onChange(of: showOnboarding) { _, isShowing in
            if !isShowing { processPendingInviteIfPossible() }
        }
        .onChange(of: celebrationBadgeID) { _, badge in
            if badge == nil { processPendingInviteIfPossible() }
        }
    }

    private func checkOnboardingStatus() {
        let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: Constants.UserDefaults.hasCompletedOnboarding)
        if !hasCompletedOnboarding {
            showOnboarding = true
        }
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
        pendingInviteMetadata = nil
        selectedTab = .spaces

        Task {
            defer { isAcceptingInvite = false }
            do {
                let space = try await DIContainer.shared.makeAcceptSpaceInviteUseCase().execute(metadata: metadata)
                pendingOpenSpace = space
            } catch {
                print("⚠️ MainTabView: failed to accept Space invite — \(error.localizedDescription)")
            }
        }
    }
}

#Preview {
    @Previewable @State var action: WidgetAction? = nil
    MainTabView(widgetAction: $action)
        .modelContainer(for: [Learning.self, Reflection.self, ImageAttachment.self, VoiceRecording.self, VideoAttachment.self], inMemory: true)
}
