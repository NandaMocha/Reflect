import Foundation
import SwiftData
import Observation
import Combine

@Observable
final class ReflectionListViewModel {
    // MARK: - State
    var reflections: [Reflection] = []
    var groupedReflections: [ReflectionDateGroup: [Reflection]] = [:]
    var searchQuery: String = ""
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
    let moveUseCase: MoveReflectionUseCaseProtocol

    var searchCancellable: AnyCancellable?
    let searchSubject = PassthroughSubject<String, Never>()
    
    // MARK: - Public Properties

    var isCreatingQuickReflection: Bool = false
    var quickReflectionError: String?

    // MARK: - Initialization

    init(
        modelContext: ModelContext,
        learning: Learning? = nil,
        searchUseCase: SearchReflectionsUseCaseProtocol? = nil,
        deleteUseCase: DeleteReflectionUseCaseProtocol? = nil,
        moveUseCase: MoveReflectionUseCaseProtocol? = nil
    ) {
        self.modelContext = modelContext
        self.learningFilter = learning
        let reflectionRepo = ReflectionRepository(modelContext: modelContext)
        let learningRepo = LearningRepository(modelContext: modelContext)
        self.searchUseCase = searchUseCase ?? SearchReflectionsUseCase(repository: reflectionRepo)
        self.deleteUseCase = deleteUseCase ?? DeleteReflectionUseCase(
            reflectionRepository: reflectionRepo
        )
        self.moveUseCase = moveUseCase ?? MoveReflectionUseCase(
            reflectionRepository: reflectionRepo,
            learningRepository: learningRepo
        )

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
