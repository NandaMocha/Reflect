import Foundation
import Observation

/// Backs a space's detail screen: its reflections, plus composing a new one and deleting
/// your own. Cache-first paint, then a sync-on-appear fetch (plan §9: fetch makes it
/// correct).
@Observable
@MainActor
final class SpaceDetailViewModel {

    // MARK: - State

    let space: Space
    var reflections: [SpaceReflection] = []
    var isRefreshing: Bool = false
    var errorMessage: String?

    // Compose
    var newTitle: String = ""
    var newPrompt: String = ""
    var isSaving: Bool = false

    // MARK: - Dependencies

    private let fetchUseCase: FetchSpaceReflectionsUseCaseProtocol
    private let createUseCase: CreateSpaceReflectionUseCaseProtocol
    private let deleteUseCase: DeleteOwnSpaceContentUseCaseProtocol
    private let repository: SpaceRepositoryProtocol

    // MARK: - Initialization

    init(
        space: Space,
        fetchUseCase: FetchSpaceReflectionsUseCaseProtocol,
        createUseCase: CreateSpaceReflectionUseCaseProtocol,
        deleteUseCase: DeleteOwnSpaceContentUseCaseProtocol,
        repository: SpaceRepositoryProtocol
    ) {
        self.space = space
        self.fetchUseCase = fetchUseCase
        self.createUseCase = createUseCase
        self.deleteUseCase = deleteUseCase
        self.repository = repository
    }

    // MARK: - Computed

    var titleCount: Int { newTitle.count }
    var titleLimit: Int { Constants.Limits.spaceReflectionTitleMaxLength }
    var promptLimit: Int { Constants.Limits.spaceReflectionPromptMaxLength }

    var canSave: Bool {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = newPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return !title.isEmpty && title.count <= titleLimit
            && !prompt.isEmpty && prompt.count <= promptLimit
            && !isSaving
    }

    // MARK: - Actions

    func load() async {
        reflections = repository.cachedReflections(spaceID: space.id)
        await refresh()
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            reflections = try await fetchUseCase.execute(for: space)
            errorMessage = nil
        } catch is CancellationError {
            // Cancelled pull-to-refresh — not a real error.
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Creates the reflection and inserts it locally (optimistic-after-ack). Returns true on
    /// success so the view can dismiss the composer.
    func save() async -> Bool {
        guard canSave else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            let reflection = try await createUseCase.execute(in: space, title: newTitle, promptText: newPrompt)
            reflections.append(reflection)
            reflections.sort { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
            newTitle = ""
            newPrompt = ""
            HapticManager.shared.success()
            return true
        } catch {
            errorMessage = error.localizedDescription
            HapticManager.shared.error()
            return false
        }
    }

    func deleteOwn(_ reflection: SpaceReflection) async {
        do {
            try await deleteUseCase.execute(reflection: reflection, in: space)
            reflections.removeAll { $0.id == reflection.id }
            HapticManager.shared.success()
        } catch {
            errorMessage = error.localizedDescription
            HapticManager.shared.error()
        }
    }
}
