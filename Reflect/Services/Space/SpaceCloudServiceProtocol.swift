import CloudKit

/// CloudKit sharing core for the Space feature: zone lifecycle, atomic root+share
/// creation, dual-database (private/shared) fetch, and share accept/leave/delete.
///
/// Implementations route every operation by `SpaceZoneRef.lane` — `.privateDB` for
/// spaces the current user owns, `.sharedDB` for spaces they've joined. Child record
/// CRUD (`SpaceReflection`, `Response`) is out of scope here; see T17.
protocol SpaceCloudServiceProtocol {
    /// Current iCloud account availability for the Space container.
    func checkAvailability() async -> CloudAvailability

    /// Creates a new custom zone in the private database, saves the root `Space`
    /// record and its `CKShare` atomically, and returns both.
    func createSpace(name: String, detail: String?, emoji: String?) async throws -> (Space, CKShare)

    /// Spaces owned by the current user (private database custom zones).
    func fetchOwnedSpaces() async throws -> [Space]

    /// Spaces the current user has joined (shared database mirrored zones).
    func fetchJoinedSpaces() async throws -> [Space]

    /// The `CKShare` for a space's root record, looked up via the correct database
    /// for `zone.lane`.
    func fetchShare(for zone: SpaceZoneRef) async throws -> CKShare

    /// Accepts an incoming share invitation and returns the resulting joined `Space`.
    func acceptShare(metadata: CKShare.Metadata) async throws -> Space

    /// Deletes a space's zone from the private database. Owner-only; destroys the
    /// space and its share for every participant.
    func deleteSpace(_ zone: SpaceZoneRef) async throws

    /// Removes the current user's mirrored zone from the shared database. Participant
    /// only; removes only their own access, leaves the space intact for others.
    func leaveSpace(_ zone: SpaceZoneRef) async throws
}
