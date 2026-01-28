import SwiftUI
import SwiftData

struct LearningListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Learning.sortOrder) private var learnings: [Learning]
    
    // State Persistence
    @AppStorage("lastOpenedLearningId") private var lastOpenedLearningId: String?
    @State private var navigationPath = NavigationPath()

    // Search
    @State private var searchText = ""

    // UI State
    @State private var showAddLearning = false
    @State private var learningToEdit: Learning?
    @State private var learningToDelete: Learning?
    @State private var showDeleteAlert = false
    @State private var showSettings = false
    @State private var isRestoringState = true

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
            .alert("Delete Learning", isPresented: $showDeleteAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    if let learning = learningToDelete {
                        deleteLearning(learning)
                    }
                }
            } message: {
                if let learning = learningToDelete {
                    Text("Are you sure you want to delete \"\(learning.title)\"? This will also delete all \(learning.reflections.count) reflections in this learning.")
                }
            }
        }
        .onAppear {
            restoreState()
        }
    }

    private func restoreState() {
        guard isRestoringState, let learningIdString = lastOpenedLearningId, let learningId = UUID(uuidString: learningIdString) else {
            return
        }
        
        // Find the learning with this ID
        if let learning = learnings.first(where: { $0.id == learningId }) {
            navigationPath.append(learning)
        }
        
        isRestoringState = false
    }

    private var emptyState: some View {
        EmptyStateView(
            icon: "book.closed",
            title: "No learnings yet",
            subtitle: "Tap + to add your first learning category",
            buttonTitle: "Add Learning"
        ) {
            showAddLearning = true
        }
    }

    private var learningList: some View {
        List {
            ForEach(filteredLearnings) { learning in
                ZStack {
                    NavigationLink(value: learning) { EmptyView() }
                        .opacity(0) // Hide default arrow
                    
                    LearningCard(learning: learning) {}
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        learningToDelete = learning
                        showDeleteAlert = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    
                    Button {
                        learningToEdit = learning
                    } label: {
                        Label("Edit", systemImage: "pencil")
                        .tint(.orange)
                    }
                }
                .contextMenu {
                    contextMenuItems(for: learning)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private func contextMenuItems(for learning: Learning) -> some View {
        Button {
            learningToEdit = learning
        } label: {
            Label("Edit", systemImage: "pencil")
        }

        Button(role: .destructive) {
            learningToDelete = learning
            showDeleteAlert = true
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private func deleteLearning(_ learning: Learning) {
        withAnimation {
            modelContext.delete(learning)
            try? modelContext.save()
            HapticManager.shared.success()
        }
    }
}

// MARK: - Filtered Reflection List

struct FilteredReflectionListView: View {
    let learning: Learning

    @Environment(\.modelContext) private var modelContext
    @Query private var reflections: [Reflection]
    
    @State private var showAddReflection = false
    @State private var reflectionToEdit: Reflection?
    @State private var reflectionToDelete: Reflection?
    @State private var showDeleteAlert = false

    @Environment(\.isSearching) private var isSearching
    @State private var searchText = ""

    var filteredReflections: [Reflection] {
        if searchText.isEmpty {
            return reflections
        } else {
            return reflections.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.plainTextContent.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    init(learning: Learning) {
        self.learning = learning
        let learningId = learning.id
        _reflections = Query(
            filter: #Predicate<Reflection> { reflection in
                reflection.learning?.id == learningId
            },
            sort: \Reflection.createdAt,
            order: .reverse
        )
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if reflections.isEmpty {
                    EmptyStateView(
                        icon: "text.book.closed",
                        title: "No reflections yet",
                        subtitle: "Start capturing your reflections for \(learning.title)"
                    )
                } else if filteredReflections.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    List {
                        ForEach(filteredReflections) { reflection in
                            ZStack {
                                NavigationLink(destination: ReflectionDetailView(reflection: reflection)) { EmptyView() }
                                    .opacity(0)
                                
                                ReflectionCard(reflection: reflection) {}
                            }
                            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    reflectionToDelete = reflection
                                    showDeleteAlert = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }

                                Button {
                                    reflectionToEdit = reflection
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.orange)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Floating Action Button - Always visible
            if !isSearching {
                FloatingActionButton(icon: "plus") {
                    showAddReflection = true
                }
                .padding(.trailing, Constants.Spacing.lg)
                .padding(.bottom, Constants.Spacing.lg)
            }
        }
        .navigationTitle("\(learning.title) Reflections")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, prompt: "Search reflections...")
        .fullScreenCover(isPresented: $showAddReflection) {
            ReflectionEditorView(mode: .create, preselectedLearning: learning)
        }
        .fullScreenCover(item: $reflectionToEdit) { reflection in
            ReflectionEditorView(mode: .edit(reflection))
        }
        .alert("Delete Reflection", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let reflection = reflectionToDelete {
                    deleteReflection(reflection)
                }
            }
        } message: {
            if let reflection = reflectionToDelete {
                Text("Are you sure you want to delete \"\(reflection.title)\"?")
            }
        }
    }

    private func deleteReflection(_ reflection: Reflection) {
        withAnimation {
            modelContext.delete(reflection)
            try? modelContext.save()
            HapticManager.shared.success()
        }
    }
}

#Preview {
    LearningListView()
        .modelContainer(for: [Learning.self, Reflection.self], inMemory: true)
}
