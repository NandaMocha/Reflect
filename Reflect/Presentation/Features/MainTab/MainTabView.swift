import SwiftUI
import SwiftData

enum MainTab {
    case learnings
    case insights
}

struct MainTabView: View {
    @State private var showOnboarding: Bool = false
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
        .onChange(of: widgetAction) { _, action in
            guard action == .insight else { return }
            selectedTab = .insights
            insightComposeSignal = true
            widgetAction = nil
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
