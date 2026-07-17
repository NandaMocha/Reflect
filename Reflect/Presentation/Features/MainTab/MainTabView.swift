import SwiftUI
import SwiftData

enum MainTab {
    case learnings
    case insights
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
    }

    private func checkOnboardingStatus() {
        let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: Constants.UserDefaults.hasCompletedOnboarding)
        if !hasCompletedOnboarding {
            showOnboarding = true
        }
    }
}

#Preview {
    @Previewable @State var action: WidgetAction? = nil
    MainTabView(widgetAction: $action)
        .modelContainer(for: [Learning.self, Reflection.self, ImageAttachment.self, VoiceRecording.self, VideoAttachment.self], inMemory: true)
}
