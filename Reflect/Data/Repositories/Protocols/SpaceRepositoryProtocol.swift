import CloudKit

/// Orchestrates the Space CloudKit core (`SpaceCloudServiceProtocol`) and the local
/// `SpaceStore` cache. The cloud is always the source of truth: every mutation goes to
/// CloudKit first and only touches the cache on success — the cache never leads.
///
/// Covers spaces and their child records (`SpaceReflection` / `SpaceResponse`).
@MainActor
protocol SpaceRepositoryProtocol {
    /// Synchronous read straight from the cache for an instant first paint. Never throws:
    /// a cache miss returns an empty array and callers refresh via `fetchSpaces`.
    func cachedSpaces() -> [Space]

    /// Merged owned + joined spaces. With `forceRefresh == false` a populated cache is
    /// returned without a network round-trip; `true` (or an empty cache) always refreshes
    /// from CloudKit and reconciles the cache.
    func fetchSpaces(forceRefresh: Bool) async throws -> [Space]

    /// Creates a space (custom zone + root record + share) in CloudKit, then caches it.
    /// Returns the new space together with the `CKShare` the cloud service created, so the
    /// caller can present the sharing controller without a race-prone re-fetch.
    func createSpace(name: String, detail: String?, emoji: String?) async throws -> (Space, CKShare)

    /// The `CKShare` backing a space's root record, for the sharing controller.
    func shareForSpace(_ space: Space) async throws -> CKShare

    /// A space's members, read live from its `CKShare`. Not cached — membership lives on
    /// the share, not in a record, so there's nothing in `SpaceStore` to reconcile.
    func members(of space: Space) async throws -> [SpaceMember]

    /// Accepts an incoming invite and caches the resulting joined space.
    func acceptInvite(metadata: CKShare.Metadata) async throws -> Space

    /// Owner-only: destroys the space for everyone, then removes it from the cache.
    func deleteSpace(_ space: Space) async throws

    /// Participant-only: drops the current user's access, then removes it from the cache.
    func leaveSpace(_ space: Space) async throws

    // MARK: - Reflections / Responses — T17

    /// Synchronous cache read of a space's reflections, for instant first paint.
    func cachedReflections(spaceID: String) -> [SpaceReflection]

    /// Fetches a space's reflections from CloudKit and reconciles the cache (scoped to this
    /// space). Returns the reconciled cache.
    func fetchReflections(for space: Space) async throws -> [SpaceReflection]

    /// Creates a reflection in the space's zone, then caches it.
    func createReflection(in space: Space, title: String, promptText: String) async throws -> SpaceReflection

    /// Synchronous cache read of a reflection's responses, for instant first paint.
    func cachedResponses(reflectionID: String) -> [SpaceResponse]

    /// Fetches a reflection's responses from CloudKit and reconciles the cache (scoped to
    /// this reflection). Returns the reconciled cache.
    func fetchResponses(for reflection: SpaceReflection, in space: Space) async throws -> [SpaceResponse]

    /// Posts a response to a reflection, then caches it.
    func createResponse(to reflection: SpaceReflection, in space: Space, body: String) async throws -> SpaceResponse

    /// Updates the body of the user's own response (cloud first, then cache). Caller guards `isMine`.
    func updateResponse(_ response: SpaceResponse, in space: Space, body: String) async throws -> SpaceResponse

    /// Deletes the user's own reflection or response (cloud first, then cache; deleting a
    /// reflection also removes its cached responses). Caller guards `isMine`.
    func deleteContent(id: String, in space: Space) async throws
}
