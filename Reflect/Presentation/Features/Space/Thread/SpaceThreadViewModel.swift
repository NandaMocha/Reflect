import Foundation
import Observation

/// Backs one reflection's response thread: chronological responses, posting, and deleting
/// your own. Cache-first paint, sync-on-appear; not real-time — designed for "recently
/// synced" (plan §11.4). Multiple responses per member are allowed (locked decision #6).
@Observable
@MainActor
final class SpaceThreadViewModel {

    // MARK: - State

    let space: Space
    let reflection: SpaceReflection
    var responses: [SpaceResponse] = []
    var isRefreshing: Bool = false
    var errorMessage: String?

    var draft: String = ""
    var isPosting: Bool = false

    // MARK: - Dependencies

    private let fetchUseCase: FetchSpaceResponsesUseCaseProtocol
    private let createUseCase: CreateSpaceResponseUseCaseProtocol
    private let deleteUseCase: DeleteOwnSpaceContentUseCaseProtocol
    private let repository: SpaceRepositoryProtocol

    // MARK: - Initialization

    init(
        space: Space,
        reflection: SpaceReflection,
        fetchUseCase: FetchSpaceResponsesUseCaseProtocol,
        createUseCase: CreateSpaceResponseUseCaseProtocol,
        deleteUseCase: DeleteOwnSpaceContentUseCaseProtocol,
        repository: SpaceRepositoryProtocol
    ) {
        self.space = space
        self.reflection = reflection
        self.fetchUseCase = fetchUseCase
        self.createUseCase = createUseCase
        self.deleteUseCase = deleteUseCase
        self.repository = repository
    }

    // MARK: - Computed

    var responseLimit: Int { Constants.Limits.spaceResponseMaxLength }
    var draftCount: Int { draft.count }

    var canPost: Bool {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= responseLimit && !isPosting
    }

    // MARK: - Actions

    func load() async {
        responses = repository.cachedResponses(reflectionID: reflection.id)
        await refresh()
    }

    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            responses = try await fetchUseCase.execute(for: reflection, in: space)
            errorMessage = nil
        } catch is CancellationError {
            // Cancelled pull-to-refresh — not a real error.
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Posts the draft and appends the returned response immediately (optimistic-after-ack)
    /// so the composer feels responsive under CloudKit latency.
    func post() async {
        guard canPost else { return }
        isPosting = true
        defer { isPosting = false }
        do {
            let response = try await createUseCase.execute(to: reflection, in: space, body: draft)
            responses.append(response)
            draft = ""
            HapticManager.shared.success()
        } catch {
            errorMessage = error.localizedDescription
            HapticManager.shared.error()
        }
    }

    func deleteOwn(_ response: SpaceResponse) async {
        do {
            try await deleteUseCase.execute(response: response, in: space)
            responses.removeAll { $0.id == response.id }
            HapticManager.shared.success()
        } catch {
            errorMessage = error.localizedDescription
            HapticManager.shared.error()
        }
    }
}
