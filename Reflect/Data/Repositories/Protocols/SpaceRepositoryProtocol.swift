import CloudKit

/// Orchestrates the Space CloudKit core (`SpaceCloudServiceProtocol`) and the local
/// `SpaceStore` cache. The cloud is always the source of truth: every mutation goes to
/// CloudKit first and only touches the cache on success — the cache never leads.
///
/// Child records (`SpaceReflection` / `SpaceResponse`) are added by T17; this protocol
/// covers spaces only.
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
    func createSpace(name: String, detail: String?, emoji: String?) async throws -> Space

    /// The `CKShare` backing a space's root record, for the sharing controller.
    func shareForSpace(_ space: Space) async throws -> CKShare

    /// Accepts an incoming invite and caches the resulting joined space.
    func acceptInvite(metadata: CKShare.Metadata) async throws -> Space

    /// Owner-only: destroys the space for everyone, then removes it from the cache.
    func deleteSpace(_ space: Space) async throws

    /// Participant-only: drops the current user's access, then removes it from the cache.
    func leaveSpace(_ space: Space) async throws
}
