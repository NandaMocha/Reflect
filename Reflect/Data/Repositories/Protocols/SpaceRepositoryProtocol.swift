import CloudKit

/// Orchestrates the Space CloudKit core (`SpaceCloudServiceProtocol`) and the local
/// `SpaceStore` cache. The cloud is always the source of truth: every mutation goes to
/// CloudKit first and only touches the cache on success — the cache never leads.
///
/// Covers spaces and their child records (`SpaceReflection`).
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
    func createSpace(name: String, detail: String?, iconName: String?, colorHex: String?) async throws -> (Space, CKShare)

    /// The `CKShare` backing a space's root record, for the sharing controller.
    func shareForSpace(_ space: Space) async throws -> CKShare

    /// A space's members, read live from its `CKShare`. Not cached — membership lives on
    /// the share, not in a record, so there's nothing in `SpaceStore` to reconcile.
    func members(of space: Space) async throws -> [SpaceMember]

    /// Registers the current user's display name into a space's shared zone so other
    /// members can see who they are. Best-effort and not cached — names live on
    /// `MemberProfile` records, resolved live inside `members(of:)`.
    func registerDisplayName(_ displayName: String, in space: Space) async throws

    /// Accepts an incoming invite and caches the resulting joined space.
    func acceptInvite(metadata: CKShare.Metadata) async throws -> Space

    /// Owner-only: destroys the space for everyone, then removes it from the cache.
    func deleteSpace(_ space: Space) async throws

    /// Participant-only: drops the current user's access, then removes it from the cache.
    func leaveSpace(_ space: Space) async throws

    // MARK: - Reflections — T17

    /// Synchronous cache read of a space's reflections, for instant first paint.
    func cachedReflections(spaceID: String) -> [SpaceReflection]

    /// Fetches a space's reflections from CloudKit and reconciles the cache (scoped to this
    /// space). Returns the reconciled cache.
    func fetchReflections(for space: Space) async throws -> [SpaceReflection]

    /// Creates a reflection in the space's zone, then caches it. `imageData` is
    /// already-compressed JPEG bytes (compression happens in the use case).
    func createReflection(in space: Space, title: String, note: String?, questions: [SpaceQuestion], imageData: Data?) async throws -> SpaceReflection

    /// Updates a reflection's title, note, and questions (edit-your-own). Any question
    /// present on `reflection` but absent from `questions` is treated as removed: every
    /// answer to that question (from any participant) is hard-deleted from CloudKit and
    /// the cache before the reflection itself is updated. Caller guards `isMine`.
    func updateReflectionQuestions(_ reflection: SpaceReflection, in space: Space, title: String, note: String?, questions: [SpaceQuestion]) async throws -> SpaceReflection

    /// Deletes the user's own reflection (cloud first, then cache; deleting a reflection
    /// also removes its cached answers). Caller guards `isMine`.
    func deleteContent(id: String, in space: Space) async throws

    // MARK: - Answers

    /// Synchronous cache read of a reflection's answers, for instant first paint.
    func cachedAnswers(reflectionID: String) -> [SpaceAnswer]

    /// Fetches a reflection's answers from CloudKit and reconciles the cache (scoped to
    /// this reflection). Returns the reconciled cache.
    func fetchAnswers(for reflection: SpaceReflection, in space: Space) async throws -> [SpaceAnswer]

    /// Creates a new answer to a question, coexisting with any other answers the user has
    /// already given to it, then caches it (cloud first, per `SpaceCloudServiceProtocol.createAnswer`).
    func createAnswer(to reflection: SpaceReflection, questionId: String, text: String, imageData: Data?, in space: Space) async throws -> SpaceAnswer

    /// Rewrites an existing answer's text and image in place, then caches it (cloud first,
    /// per `SpaceCloudServiceProtocol.updateAnswer`).
    func updateAnswer(_ answer: SpaceAnswer, text: String, imageData: Data?, in space: Space) async throws -> SpaceAnswer

    /// Deletes the user's own answer (cloud first, then cache row removal). Caller guards `isMine`.
    func deleteOwnAnswer(_ answer: SpaceAnswer, in space: Space) async throws
}
