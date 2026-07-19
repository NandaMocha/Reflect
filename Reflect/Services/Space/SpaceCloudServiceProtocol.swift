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

    // MARK: - Child records (SpaceReflection / Response) — T17

    /// All reflections in a space's zone, with `isMine` resolved against the current user
    /// and `authorDisplayName` resolved from the zone's `CKShare` participants.
    func fetchReflections(in zone: SpaceZoneRef) async throws -> [SpaceReflection]

    /// Creates a reflection as a child of the root `Space` record (parent reference set so
    /// the share reaches it). Writes to the zone's database per `zone.lane`.
    func createReflection(in zone: SpaceZoneRef, spaceID: String, title: String, promptText: String) async throws -> SpaceReflection

    /// All responses belonging to `reflection`, resolved like `fetchReflections`.
    func fetchResponses(for reflection: SpaceReflection, in zone: SpaceZoneRef) async throws -> [SpaceResponse]

    /// Creates a response as a child of its `SpaceReflection` record.
    func createResponse(to reflection: SpaceReflection, body: String, in zone: SpaceZoneRef) async throws -> SpaceResponse

    /// Deletes a single child record (reflection or response) by record name. UI-level
    /// trust: the caller guards `isMine` (no server enforcement, plan §11.2).
    func deleteRecord(id: String, in zone: SpaceZoneRef) async throws
}
