import SwiftUI
import SwiftData

struct FilteredReflectionListView: View {
    let learning: Learning

    @Environment(\.modelContext) private var modelContext
    @Query private var reflections: [Reflection]

    @State var showAddReflection = false
    @State var reflectionToEdit: Reflection?
    @State var reflectionToDelete: Reflection?
    @State var showDeleteAlert = false

    @Environment(\.isSearching) private var isSearching
    @State var searchText = ""

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
                            .standardSwipeActions {
                                reflectionToDelete = reflection
                                showDeleteAlert = true
                            } onEdit: {
                                reflectionToEdit = reflection
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

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
        .deleteConfirmationAlert(
            itemName: "Reflection",
            isPresented: $showDeleteAlert,
            additionalMessage: reflectionToDelete.map {
                "Are you sure you want to delete \"\($0.title)\"?"
            }
        ) {
            if let reflection = reflectionToDelete {
                deleteReflection(reflection)
            }
        }
    }

    func deleteReflection(_ reflection: Reflection) {
        withAnimation {
            modelContext.delete(reflection)
            try? modelContext.save()
            HapticManager.shared.success()
        }
    }
}
