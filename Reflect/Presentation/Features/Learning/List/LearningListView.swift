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
                FilteredReflectionListView(learning: learning)
                    .onAppear {
                        lastOpenedLearningId = learning.id.uuidString
                    }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        HapticManager.shared.lightImpact()
                        showSettings = true
                    } label: {
                        Image(systemName: "person.circle")
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
            restoreState()
        }
    }

    func restoreState() {
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
}

#Preview {
    LearningListView()
        .modelContainer(for: [Learning.self, Reflection.self], inMemory: true)
}
