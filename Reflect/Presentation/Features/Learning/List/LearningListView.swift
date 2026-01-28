import SwiftUI
import SwiftData

struct LearningListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Learning.sortOrder) private var learnings: [Learning]

    @State private var showAddLearning = false
    @State private var learningToEdit: Learning?
    @State private var learningToDelete: Learning?
    @State private var showDeleteAlert = false
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            Group {
                if learnings.isEmpty {
                    emptyState
                } else {
                    learningList
                }
            }
            .navigationTitle("Learnings")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        HapticManager.shared.lightImpact()
                        showSettings = true
                    } label: {
                        Image(systemName: "person.circle.fill")
                            .font(.title3)
                            .foregroundColor(.primaryDefault)
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
            ForEach(learnings) { learning in
                ZStack {
                    NavigationLink(destination: FilteredReflectionListView(learning: learning)) {}
                    LearningCard(learning: learning) {}
                }
                .listRowInsets(EdgeInsets(top: Constants.Spacing.sm,
                                          leading: Constants.Spacing.md,
                                          bottom: Constants.Spacing.sm,
                                          trailing: Constants.Spacing.md))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        learningToDelete = learning
                        showDeleteAlert = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .contextMenu {
                    contextMenuItems(for: learning)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
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
                } else {
                    ScrollView {
                        LazyVStack(spacing: Constants.Spacing.sm) {
                            ForEach(reflections) { reflection in
                                NavigationLink(destination: ReflectionDetailView(reflection: reflection)) {
                                    ReflectionCard(reflection: reflection) {}
                                }
                                .buttonStyle(.plain)
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
                        .padding(.horizontal, Constants.Spacing.md)
                        .padding(.vertical, Constants.Spacing.sm)
                        .padding(.bottom, 80) // Space for FAB
                    }
                }
            }
            
            // Floating Action Button
            FloatingActionButton(icon: "plus") {
                showAddReflection = true
            }
            .padding(.trailing, Constants.Spacing.lg)
            .padding(.bottom, Constants.Spacing.lg)
        }
        .navigationTitle("\(learning.title) Reflections")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showAddReflection) {
            ReflectionEditorView(mode: .create, preselectedLearning: learning)
        }
        .sheet(item: $reflectionToEdit) { reflection in
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
