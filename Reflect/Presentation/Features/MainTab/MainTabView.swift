import SwiftUI
import SwiftData

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

    init(widgetAction: Binding<WidgetAction?> = .constant(nil)) {
        self._widgetAction = widgetAction
    }

    var body: some View {
        LearningListView(widgetAction: $widgetAction)
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
