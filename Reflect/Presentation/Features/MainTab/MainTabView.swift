import SwiftUI
import SwiftData

struct MainTabView: View {
    @State private var showOnboarding: Bool = false
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
