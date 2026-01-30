import SwiftUI
import SwiftData

struct MainTabView: View {
    @State private var showOnboarding: Bool = false
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        LearningListView()
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
    MainTabView()
        .modelContainer(for: [Learning.self, Reflection.self, ImageAttachment.self, VoiceRecording.self, VideoAttachment.self], inMemory: true)
}
