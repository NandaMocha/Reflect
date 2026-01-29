import SwiftUI
import SwiftData

struct ReflectionListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Reflection.createdAt, order: .reverse) private var reflections: [Reflection]
    @Query(sort: \Hashtag.name) private var hashtags: [Hashtag]

    @State private var searchText = ""
    @State private var selectedHashtags: Set<String> = []
    @State private var showFilters = false
    @State private var sortOption: Constants.SortOption = .newestFirst

    private var filteredReflections: [Reflection] {
        var result = reflections

        // Filter by search text
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter { reflection in
                reflection.title.lowercased().contains(query) ||
                reflection.plainTextContent.lowercased().contains(query) ||
                reflection.hashtags.contains { $0.name.lowercased().contains(query) }
            }
        }

        // Filter by selected hashtags
        if !selectedHashtags.isEmpty {
            result = result.filter { reflection in
                let reflectionHashtags = Set(reflection.hashtags.map { $0.name.lowercased() })
                return !reflectionHashtags.isDisjoint(with: selectedHashtags.map { $0.lowercased() })
            }
        }

        // Sort
        switch sortOption {
        case .newestFirst:
            result.sort { $0.createdAt > $1.createdAt }
        case .oldestFirst:
            result.sort { $0.createdAt < $1.createdAt }
        case .alphabeticalAZ:
            result.sort { $0.title.lowercased() < $1.title.lowercased() }
        case .alphabeticalZA:
            result.sort { $0.title.lowercased() > $1.title.lowercased() }
        case .recentlyUpdated:
            result.sort { $0.updatedAt > $1.updatedAt }
        }

        return result
    }

    private var groupedReflections: [(String, [Reflection])] {
        let grouped = Dictionary(grouping: filteredReflections) { reflection in
            reflection.createdAt.sectionHeader
        }
        return grouped.sorted { $0.value.first?.createdAt ?? Date() > $1.value.first?.createdAt ?? Date() }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if reflections.isEmpty {
                        emptyState
                    } else if filteredReflections.isEmpty {
                        noResultsState
                    } else {
                        reflectionList
                    }
                }

                // FAB
                if !reflections.isEmpty {
                    NavigationLink(destination: ReflectionEditorView(mode: .create)) {
                        FloatingActionButton(icon: "plus") {}
                    }
                    .padding(Constants.Spacing.lg)
                }
            }
            .navigationTitle("Reflections")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        sortingMenu
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search reflections...")
        }
    }

    // MARK: - Views

    private var emptyState: some View {
        VStack(spacing: Constants.Spacing.lg) {
            EmptyStateView(
                icon: "text.book.closed",
                title: "Start Your Journey",
                subtitle: "Capture your first learning reflection",
                buttonTitle: "Create Reflection",
                buttonAction: {
                    // Navigation handled by NavigationLink
                }
            )

            NavigationLink(destination: ReflectionEditorView(mode: .create)) {
                PrimaryButton("Create First Reflection", icon: "plus") {}
            }
            .frame(maxWidth: 250)
        }
    }

    private var noResultsState: some View {
        EmptyStateView(
            icon: "magnifyingglass",
            title: "No Results Found",
            subtitle: "Try different keywords or clear filters",
            buttonTitle: "Clear Filters",
            buttonAction: {
                searchText = ""
                selectedHashtags.removeAll()
            }
        )
    }

    private var reflectionList: some View {
        List {
            if !hashtags.isEmpty {
                hashtagChips
            }
            
            ForEach(groupedReflections, id: \.0) { section, sectionReflections in
                Section {
                    ForEach(sectionReflections) { reflection in
                        NavigationLink(destination: ReflectionDetailView(reflection: reflection)) {
                            ReflectionCard(reflection: reflection) {}
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    DateSectionHeader(date: sectionReflections.first?.createdAt ?? Date())
                        .background(Color(.systemBackground).opacity(0.95))
                }
            }
            
            .padding(.horizontal, Constants.Spacing.md)
            .padding(.bottom, 50) // Space for FAB

        }
    }

    private var hashtagChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Constants.Spacing.xs) {
                // All chip
                HashtagChip(
                    text: "All",
                    isSelected: selectedHashtags.isEmpty,
                    showHashSymbol: false
                ) {
                    selectedHashtags.removeAll()
                    HapticManager.shared.selection()
                }

                // Hashtag chips
                ForEach(hashtags.sorted(by: { $0.usageCount > $1.usageCount }).prefix(10)) { hashtag in
                    HashtagChip(
                        text: hashtag.name,
                        isSelected: selectedHashtags.contains(hashtag.name)
                    ) {
                        if selectedHashtags.contains(hashtag.name) {
                            selectedHashtags.remove(hashtag.name)
                        } else {
                            selectedHashtags.insert(hashtag.name)
                        }
                        HapticManager.shared.selection()
                    }
                }
            }
            .padding(.horizontal, Constants.Spacing.md)
            .padding(.vertical, Constants.Spacing.sm)
        }
    }

    private var sortingMenu: some View {
        Section("Sort By") {
            ForEach(Constants.SortOption.allCases, id: \.self) { option in
                Button {
                    sortOption = option
                } label: {
                    HStack {
                        Text(option.title)
                        if sortOption == option {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Date Extension for Section Headers

private extension Date {
    var sectionHeader: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) {
            return "Today"
        } else if calendar.isDateInYesterday(self) {
            return "Yesterday"
        } else if calendar.isDate(self, equalTo: Date(), toGranularity: .weekOfYear) {
            return "This Week"
        } else if calendar.isDate(self, equalTo: Date(), toGranularity: .month) {
            return "This Month"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: self)
        }
    }
}

#Preview {
    ReflectionListView()
        .modelContainer(for: [Learning.self, Reflection.self, Hashtag.self], inMemory: true)
}
