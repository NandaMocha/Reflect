import Foundation
import Observation

/// Backs the Spaces list. Paints instantly from the cache, then reconciles against
/// CloudKit; all mutations go through use cases (which carry the owner/participant
/// guards). The cloud service is used only for the read-only availability probe — no
/// data mutation touches it directly.
@Observable
@MainActor
final class SpaceListViewModel {

    // MARK: - State

    var spaces: [Space] = []
    var availability: CloudAvailability = .available
    var isRefreshing: Bool = false
    var errorMessage: String?

    /// True when iCloud isn't usable, so the list shows the sign-in state instead.
    var showsUnavailableState: Bool { !availability.isAvailable }

    // MARK: - Dependencies

    private let fetchUseCase: FetchSpacesUseCaseProtocol
    private let deleteUseCase: DeleteSpaceUseCaseProtocol
    private let leaveUseCase: LeaveSpaceUseCaseProtocol
    private let repository: SpaceRepositoryProtocol       // cachedSpaces() — instant paint only
    private let cloudService: SpaceCloudServiceProtocol   // checkAvailability() — read-only

    // MARK: - Initialization

    init(
        fetchUseCase: FetchSpacesUseCaseProtocol,
        deleteUseCase: DeleteSpaceUseCaseProtocol,
        leaveUseCase: LeaveSpaceUseCaseProtocol,
        repository: SpaceRepositoryProtocol,
        cloudService: SpaceCloudServiceProtocol
    ) {
        self.fetchUseCase = fetchUseCase
        self.deleteUseCase = deleteUseCase
        self.leaveUseCase = leaveUseCase
        self.repository = repository
        self.cloudService = cloudService
    }

    // MARK: - Actions

    /// First paint: synchronous cache read, then a real network reconcile (so a space
    /// deleted/left on another device doesn't linger across launches).
    func load() async {
        spaces = repository.cachedSpaces()
        await refresh(force: true)
    }

    /// Repaints from the local cache without a network round-trip. Used right after an
    /// invite accept, where a forced reconcile could momentarily evict the just-joined
    /// zone before CloudKit mirrors it into the shared database.
    func reloadFromCache() {
        spaces = repository.cachedSpaces()
    }

    func refresh(force: Bool) async {
        isRefreshing = true
        defer { isRefreshing = false }

        availability = await cloudService.checkAvailability()
        guard availability.isAvailable else {
            // Keep the cached paint; the unavailable state explains the rest.
            return
        }

        do {
            spaces = try await fetchUseCase.execute(forceRefresh: force)
            errorMessage = nil
        } catch is CancellationError {
            // A cancelled pull-to-refresh (e.g. the user navigated away mid-pull) isn't
            // a real error — don't surface it.
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ space: Space) async {
        do {
            try await deleteUseCase.execute(space: space)
            spaces.removeAll { $0.id == space.id }
            HapticManager.shared.success()
        } catch {
            errorMessage = error.localizedDescription
            HapticManager.shared.error()
        }
    }

    func leave(_ space: Space) async {
        do {
            try await leaveUseCase.execute(space: space)
            spaces.removeAll { $0.id == space.id }
            HapticManager.shared.success()
        } catch {
            errorMessage = error.localizedDescription
            HapticManager.shared.error()
        }
    }
}
