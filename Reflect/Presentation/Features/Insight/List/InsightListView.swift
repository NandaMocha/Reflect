import SwiftUI
import SwiftData

struct InsightListView: View {
    @Query(sort: \Insight.createdAt, order: .reverse) private var insights: [Insight]

    @State private var viewModel = DIContainer.shared.makeInsightListViewModel()

    // Sheet presentation state
    @State private var showComposeSheet = false
    @State private var insightToEdit: Insight?

    // Deep-link compose hook: flips to true to trigger the compose sheet, e.g. from `reflect://insight`.
    var composeSignal: Binding<Bool>

    init(composeSignal: Binding<Bool> = .constant(false)) {
        self.composeSignal = composeSignal
    }

    private var groupedInsights: [(group: InsightDateGroup, insights: [Insight])] {
        viewModel.filteredAndGrouped(insights)
    }

    var body: some View {
        NavigationStack {
            Group {
                if insights.isEmpty {
                    emptyState
                } else if groupedInsights.isEmpty {
                    noResultsState
                } else {
                    insightList
                }
            }
            .navigationTitle("Insights")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    filterMenu
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        HapticManager.shared.lightImpact()
                        showComposeSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .searchable(text: $viewModel.searchQuery, prompt: "Search insights...")
            .sheet(isPresented: $showComposeSheet) {
                InsightEditorView(mode: .create)
            }
            .sheet(item: $insightToEdit) { insight in
                InsightEditorView(mode: .edit(insight))
            }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK", role: .cancel) {
                    viewModel.errorMessage = nil
                }
            } message: {
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                }
            }
            .onChange(of: composeSignal.wrappedValue) { _, newValue in
                guard newValue else { return }
                showComposeSheet = true
                composeSignal.wrappedValue = false
            }
        }
    }

    // MARK: - Filter Menu

    private var filterMenu: some View {
        Menu {
            Button {
                HapticManager.shared.selection()
                viewModel.typeFilter = nil
            } label: {
                HStack {
                    Text("All")
                    if viewModel.typeFilter == nil {
                        Image(systemName: "checkmark")
                    }
                }
            }

            ForEach(InsightType.allCases) { type in
                Button {
                    HapticManager.shared.selection()
                    viewModel.typeFilter = type
                } label: {
                    HStack {
                        Text(type.pluralTitle)
                        if viewModel.typeFilter == type {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Image(systemName: viewModel.typeFilter == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
        }
    }

    // MARK: - List

    private var insightList: some View {
        List {
            ForEach(groupedInsights, id: \.group) { entry in
                Section {
                    ForEach(entry.insights) { insight in
                        InsightCard(insight: insight) {
                            insightToEdit = insight
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                Task {
                                    await viewModel.delete(insight)
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                } header: {
                    Text(entry.group.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .padding(.leading, 4)
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Empty States

    private var emptyState: some View {
        EmptyStateView(
            icon: "lightbulb",
            title: "No insights yet",
            subtitle: "Capture a quick question, note, or reflection whenever one crosses your mind",
            buttonTitle: "New Insight",
            buttonAction: {
                showComposeSheet = true
            }
        )
    }

    private var noResultsState: some View {
        EmptyStateView(
            icon: "magnifyingglass",
            title: "No Results Found",
            subtitle: viewModel.typeFilter != nil ? "No insights match this filter" : "Try different keywords",
            buttonTitle: "Clear Filters",
            buttonAction: {
                viewModel.searchQuery = ""
                viewModel.typeFilter = nil
            }
        )
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Insight.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )

    let sampleInsights = [
        Insight(text: "What's the difference between actors and classes in Swift 6?", type: .question),
        Insight(text: "SwiftData's @Model macro generates a lot of boilerplate under the hood.", type: .note),
        Insight(text: "I keep reaching for force-unwraps when I'm tired — worth a habit check.", type: .reflection)
    ]
    for insight in sampleInsights {
        container.mainContext.insert(insight)
    }

    return InsightListView()
        .modelContainer(container)
}
