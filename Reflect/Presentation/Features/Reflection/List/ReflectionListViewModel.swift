import Foundation
import SwiftData
import Observation
import Combine

@Observable
final class ReflectionListViewModel {
    // MARK: - State
    var reflections: [Reflection] = []
    var groupedReflections: [DateGroup: [Reflection]] = [:]
    var popularHashtags: [Hashtag] = []
    var searchQuery: String = ""
    var selectedHashtags: Set<String> = []
    var sortOption: Constants.SortOption = .newestFirst
    var isLoading: Bool = false
    var errorMessage: String?

    // MARK: - Filters
    var learningFilter: Learning?
    var showFavoritesOnly: Bool = false

    // MARK: - Dependencies
    private let modelContext: ModelContext
    private let searchUseCase: SearchReflectionsUseCaseProtocol
    private let deleteUseCase: DeleteReflectionUseCaseProtocol
    private let hashtagRepository: HashtagRepositoryProtocol

    private var searchCancellable: AnyCancellable?
    private let searchSubject = PassthroughSubject<String, Never>()

    // MARK: - Date Grouping

    enum DateGroup: Hashable, Comparable {
        case today
        case yesterday
        case thisWeek
        case thisMonth
        case older(Date)

        var title: String {
            switch self {
            case .today: return "Today"
            case .yesterday: return "Yesterday"
            case .thisWeek: return "This Week"
            case .thisMonth: return "This Month"
            case .older(let date): return date.monthYearFormatted
            }
        }

        static func < (lhs: DateGroup, rhs: DateGroup) -> Bool {
            switch (lhs, rhs) {
            case (.today, _): return true
            case (_, .today): return false
            case (.yesterday, _): return true
            case (_, .yesterday): return false
            case (.thisWeek, _): return true
            case (_, .thisWeek): return false
            case (.thisMonth, _): return true
            case (_, .thisMonth): return false
            case (.older(let lhsDate), .older(let rhsDate)): return lhsDate > rhsDate
            }
        }
    }

    // MARK: - Initialization

    init(
        modelContext: ModelContext,
        searchUseCase: SearchReflectionsUseCaseProtocol? = nil,
        deleteUseCase: DeleteReflectionUseCaseProtocol? = nil,
        hashtagRepository: HashtagRepositoryProtocol? = nil
    ) {
        self.modelContext = modelContext
        let reflectionRepo = ReflectionRepository(modelContext: modelContext)
        let hashtagRepo = HashtagRepository(modelContext: modelContext)
        self.searchUseCase = searchUseCase ?? SearchReflectionsUseCase(repository: reflectionRepo)
        self.deleteUseCase = deleteUseCase ?? DeleteReflectionUseCase(
            reflectionRepository: reflectionRepo,
            hashtagRepository: hashtagRepo
        )
        self.hashtagRepository = hashtagRepository ?? hashtagRepo

        setupSearchDebounce()
    }

    // MARK: - Setup

    private func setupSearchDebounce() {
        searchCancellable = searchSubject
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.performSearch()
                }
            }
    }

    // MARK: - Data Loading

    @MainActor
    func loadReflections() async {
        isLoading = true
        errorMessage = nil

        do {
            let filters = buildFilters()
            reflections = try await searchUseCase.execute(filters: filters)
            groupReflectionsByDate()
            await loadPopularHashtags()
            isLoading = false
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func loadPopularHashtags() async {
        do {
            popularHashtags = try await hashtagRepository.fetchPopular(limit: 10)
        } catch {
            popularHashtags = []
        }
    }

    // MARK: - Search

    func updateSearchQuery(_ query: String) {
        searchQuery = query
        searchSubject.send(query)
    }

    @MainActor
    private func performSearch() async {
        await loadReflections()
    }

    // MARK: - Filtering

    func toggleHashtag(_ hashtag: String) {
        if selectedHashtags.contains(hashtag) {
            selectedHashtags.remove(hashtag)
        } else {
            selectedHashtags.insert(hashtag)
        }
        HapticManager.shared.selection()
        Task { @MainActor in
            await loadReflections()
        }
    }

    func clearFilters() {
        selectedHashtags.removeAll()
        showFavoritesOnly = false
        learningFilter = nil
        searchQuery = ""
        Task { @MainActor in
            await loadReflections()
        }
    }

    func setLearningFilter(_ learning: Learning?) {
        learningFilter = learning
        Task { @MainActor in
            await loadReflections()
        }
    }

    func toggleFavorites() {
        showFavoritesOnly.toggle()
        Task { @MainActor in
            await loadReflections()
        }
    }

    func updateSortOption(_ option: Constants.SortOption) {
        sortOption = option
        Task { @MainActor in
            await loadReflections()
        }
    }

    private func buildFilters() -> SearchFilters {
        SearchFilters(
            query: searchQuery,
            learningId: learningFilter?.id,
            hashtags: Array(selectedHashtags),
            favoritesOnly: showFavoritesOnly,
            sortOption: sortOption
        )
    }

    // MARK: - Grouping

    private func groupReflectionsByDate() {
        var groups: [DateGroup: [Reflection]] = [:]
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        for reflection in reflections {
            let reflectionDate = calendar.startOfDay(for: reflection.createdAt)
            let group: DateGroup

            if reflectionDate == today {
                group = .today
            } else if reflectionDate == calendar.date(byAdding: .day, value: -1, to: today) {
                group = .yesterday
            } else if let weekAgo = calendar.date(byAdding: .day, value: -7, to: today),
                      reflectionDate > weekAgo {
                group = .thisWeek
            } else if let monthAgo = calendar.date(byAdding: .month, value: -1, to: today),
                      reflectionDate > monthAgo {
                group = .thisMonth
            } else {
                group = .older(reflectionDate)
            }

            groups[group, default: []].append(reflection)
        }

        groupedReflections = groups
    }

    var sortedDateGroups: [DateGroup] {
        groupedReflections.keys.sorted()
    }

    // MARK: - Actions

    @MainActor
    func deleteReflection(_ reflection: Reflection) async {
        do {
            try await deleteUseCase.execute(reflection: reflection)
            reflections.removeAll { $0.id == reflection.id }
            groupReflectionsByDate()
            HapticManager.shared.success()
        } catch {
            errorMessage = error.localizedDescription
            HapticManager.shared.error()
        }
    }

    @MainActor
    func toggleFavorite(_ reflection: Reflection) async {
        reflection.isFavorite.toggle()
        reflection.updatedAt = Date()
        try? modelContext.save()
        HapticManager.shared.selection()
    }

    // MARK: - Computed Properties

    var hasActiveFilters: Bool {
        !selectedHashtags.isEmpty || showFavoritesOnly || learningFilter != nil || !searchQuery.isEmpty
    }

    var isEmpty: Bool {
        reflections.isEmpty && !isLoading
    }

    var emptyStateMessage: String {
        if hasActiveFilters {
            return "No reflections match your filters"
        }
        return "Start your journey by creating your first reflection"
    }
}
