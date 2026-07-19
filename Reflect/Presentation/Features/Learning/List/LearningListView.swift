import SwiftUI
import SwiftData

struct LearningListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Learning.sortOrder) private var learnings: [Learning]

    // State Persistence
    @AppStorage("lastOpenedLearningId") private var lastOpenedLearningId: String?
    @State var navigationPath = NavigationPath()

    // Search
    @State var searchText = ""

    // UI State
    @State var showAddLearning = false
    @State var learningToEdit: Learning?
    @State var learningToDelete: Learning?
    @State var showDeleteAlert = false
    @State var showSettings = false
    @State var isRestoringState = true
    @State var showAchievementGallery = false

    // Achievement State
    @State private var badges: [Badge] = []

    // Widget action handling
    @Binding var widgetAction: WidgetAction?

    // Navigation to specific learning for widget
    @State private var navigateToLearningId: UUID?

    // Track if we're navigating from widget (skip restoreState)
    @State private var isNavigatingFromWidget = false

    init(widgetAction: Binding<WidgetAction?> = .constant(nil)) {
        self._widgetAction = widgetAction
    }

    var filteredLearnings: [Learning] {
        if searchText.isEmpty {
            return learnings
        } else {
            return learnings.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if learnings.isEmpty {
                    emptyState
                } else if filteredLearnings.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    learningList
                }
            }
            .navigationTitle("Learnings")
            .navigationDestination(for: Learning.self) { learning in
                ReflectionListView(learning: learning, widgetAction: $widgetAction)
                    .onAppear {
                        lastOpenedLearningId = learning.id.uuidString
                    }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        HapticManager.shared.lightImpact()
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.title3)
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        HapticManager.shared.lightImpact()
                        showAddLearning = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddLearning) {
                LearningFormView(mode: .create)
            }
            .sheet(item: $learningToEdit) { learning in
                LearningFormView(mode: .edit(learning))
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showAchievementGallery) {
                AchievementGallerySheet(isPresented: $showAchievementGallery, modelContext: modelContext)
            }
            .onDisappear {
                // Observers are automatically cleaned up when view is deallocated
            }
            .deleteConfirmationAlert(
                itemName: "Learning",
                isPresented: $showDeleteAlert,
                additionalMessage: learningToDelete.map {
                    "Are you sure you want to delete \"\($0.title)\"? This will also delete all \($0.reflections.count) reflections in this learning."
                }
            ) {
                if let learning = learningToDelete {
                    deleteLearning(learning)
                }
            }
        }
        .onAppear {
            loadBadges()
            restoreState()
        }
        .onReceive(NotificationCenter.default.publisher(for: .badgeProgressDidUpdate)) { _ in
            loadBadges()
        }
        .onReceive(NotificationCenter.default.publisher(for: .badgesDidUnlock)) { _ in
            loadBadges()
        }
        .onChange(of: showAchievementGallery) { _, newValue in
            if !newValue {
                // Reload badges when gallery is dismissed
                loadBadges()
            }
        }
        .onChange(of: widgetAction) { _, action in
            handleWidgetAction(action)
        }
    }

    // MARK: - Widget Action Handling

    private func handleWidgetAction(_ action: WidgetAction?) {
        if action == .insight { return }

        guard let action = action else { return }

        // Get the target learning
        let targetLearning = getTargetLearning()

        guard let learning = targetLearning else {
            // No learning exists, show onboarding/create learning
            showAddLearning = true
            widgetAction = nil
            return
        }

        // Clear any existing navigation to prevent duplicates
        navigationPath.removeLast(navigationPath.count)

        // Disable restoration to prevent it from interfering
        isRestoringState = false

        // Set flag to prevent restoreState from interfering
        isNavigatingFromWidget = true

        // Navigate to the learning's reflection list
        navigationPath.append(learning)

        // Small delay to ensure navigation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // The action will be handled by ReflectionListView
            widgetAction = nil
            // Reset flag after widget flow completes
            isNavigatingFromWidget = false
        }
    }

    private func getTargetLearning() -> Learning? {
        // Try last used learning first
        if let lastUsedId = UserDefaults.standard.lastUsedLearningId(),
           let lastUsed = learnings.first(where: { $0.id == lastUsedId }) {
            return lastUsed
        }

        // Fall back to first learning by sort order
        return learnings.first
    }

    func restoreState() {
        // Skip restoration if we're navigating from widget OR if widget action is pending
        if isNavigatingFromWidget || widgetAction != nil {
            return
        }

        guard isRestoringState, let learningIdString = lastOpenedLearningId, let learningId = UUID(uuidString: learningIdString) else {
            return
        }

        if let learning = learnings.first(where: { $0.id == learningId }) {
            navigationPath.append(learning)
        }

        isRestoringState = false
    }

    var emptyState: some View {
        EmptyStateView(
            icon: "book.closed",
            title: "No learnings yet",
            subtitle: "Tap + to add your first learning category",
            buttonTitle: "Add Learning"
        ) {
            showAddLearning = true
        }
    }

    var learningList: some View {
        List {
            // Achievement Entry Section
            achievementEntrySection

            ForEach(filteredLearnings) { learning in
                ZStack {
                    NavigationLink(value: learning) { EmptyView() }
                        .opacity(0)

                    LearningCard(learning: learning) {}
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .standardSwipeActions {
                    learningToDelete = learning
                    showDeleteAlert = true
                } onEdit: {
                    learningToEdit = learning
                }
                .standardContextMenu(
                    onEdit: { learningToEdit = learning },
                    onDelete: {
                        learningToDelete = learning
                        showDeleteAlert = true
                    }
                )
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
    }

    func deleteLearning(_ learning: Learning) {
        withAnimation {
            modelContext.delete(learning)
            try? modelContext.save()
            HapticManager.shared.success()
        }
    }

    // MARK: - Achievement Entry Section

    private var achievementEntrySection: some View {
        Section {
            VStack {
                Button {
                    HapticManager.shared.lightImpact()
                    showAchievementGallery = true
                } label: {
                    HStack(spacing: 16) {
                        // Achievement Title & Count
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Achievements")
                                .font(.headline)
                                .foregroundStyle(.primary)
                        }
                        
                        Spacer()
                        
                        // Latest 4 Achievement Icons
                        if !latestAchievements.isEmpty {
                            HStack(spacing: 8) {
                                ForEach(latestAchievements.prefix(4)) { badge in
                                    Image(systemName: badge.icon)
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundStyle(.blue)
                                        .frame(width: 40, height: 40)
                                        .background(Color.blue.opacity(0.1))
                                        .clipShape(Circle())
                                }
                                
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        } else {
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                
                Divider()
            }
        }
        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private var latestAchievements: [Badge] {
        badges.filter { $0.isUnlocked }
            .sorted { ($0.unlockedAt ?? .distantPast) > ($1.unlockedAt ?? .distantPast) }
    }

    // MARK: - Load Badges

    private func loadBadges() {
        let descriptor = FetchDescriptor<Badge>()
        badges = (try? modelContext.fetch(descriptor)) ?? []
    }
}

/// Owns its `BadgeGridViewModel` via `@State` so it's created once, not rebuilt on every
/// parent re-render (the previous inline-in-sheet-closure VM was the documented "orphaned
/// ViewModel" bug — see docs/reviews/achievement-counter-root-cause.md).
private struct AchievementGallerySheet: View {
    @Binding var isPresented: Bool
    @State private var viewModel: BadgeGridViewModel

    init(isPresented: Binding<Bool>, modelContext: ModelContext) {
        _isPresented = isPresented
        _viewModel = State(initialValue: BadgeGridViewModel(modelContext: modelContext))
    }

    var body: some View {
        NavigationStack {
            BadgeGridView(viewModel: viewModel)
                .navigationTitle("Achievements")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { isPresented = false }
                    }
                }
        }
    }
}

#Preview {
    @Previewable @State var action: WidgetAction? = nil
    LearningListView(widgetAction: $action)
        .modelContainer(for: [Learning.self, Reflection.self], inMemory: true)
}
