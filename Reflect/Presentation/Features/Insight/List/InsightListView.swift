import SwiftUI
import SwiftData

struct InsightListView: View {
    @Query(sort: \Insight.createdAt, order: .reverse) private var insights: [Insight]

    @State private var viewModel = DIContainer.shared.makeInsightListViewModel()

    // Sheet presentation state
    @State private var showComposeSheet = false
    @State private var insightToEdit: Insight?
    @State private var showSettings = false

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
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if insights.isEmpty {
                        emptyState
                    } else if groupedInsights.isEmpty {
                        noResultsState
                    } else {
                        insightList
                    }
                }

                // Floating action button — matches the Reflections list
                if !insights.isEmpty {
                    FloatingActionButton {
                        showComposeSheet = true
                    }
                    .padding(Constants.Spacing.lg)
                }
            }
            .navigationTitle("Insights")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    SettingsToolbarButton { showSettings = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    filterMenu
                }
            }
            .searchable(text: $viewModel.searchQuery, prompt: "Search insights...", isActive: !insights.isEmpty)
            .sheet(isPresented: $showComposeSheet) {
                InsightEditorView(mode: .create)
            }
            .sheet(item: $insightToEdit) { insight in
                InsightEditorView(mode: .edit(insight))
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .errorAlert($viewModel.errorMessage, title: "Error")
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
            Section("Type") {
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
            }

            Section("Follow-up") {
                ForEach(InsightFollowUpFilter.allCases, id: \.self) { option in
                    Button {
                        HapticManager.shared.selection()
                        viewModel.followUpFilter = option
                    } label: {
                        HStack {
                            Text(option.title)
                            if viewModel.followUpFilter == option {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        } label: {
            Image(systemName: viewModel.isFiltering ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
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
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
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
            subtitle: viewModel.isFiltering ? "No insights match this filter" : "Try different keywords",
            buttonTitle: "Clear Filters",
            buttonAction: {
                viewModel.searchQuery = ""
                viewModel.typeFilter = nil
                viewModel.followUpFilter = .all
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
        Insight(text: "I keep reaching for force-unwraps when I'm tired — worth a habit check.", type: .question)
    ]
    for insight in sampleInsights {
        container.mainContext.insert(insight)
    }

    return InsightListView()
        .modelContainer(container)
}
