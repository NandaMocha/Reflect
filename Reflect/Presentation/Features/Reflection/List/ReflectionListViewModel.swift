import Foundation
import SwiftData
import Observation
import Combine

@Observable
final class ReflectionListViewModel {
    // MARK: - State
    var reflections: [Reflection] = []
    var groupedReflections: [ReflectionDateGroup: [Reflection]] = [:]
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
    let modelContext: ModelContext
    let searchUseCase: SearchReflectionsUseCaseProtocol
    let deleteUseCase: DeleteReflectionUseCaseProtocol
    let hashtagRepository: HashtagRepositoryProtocol

    var searchCancellable: AnyCancellable?
    let searchSubject = PassthroughSubject<String, Never>()

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

    func setupSearchDebounce() {
        searchCancellable = searchSubject
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.performSearch()
                }
            }
    }
}
