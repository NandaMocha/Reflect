# Space Feature — Task Breakdown

> Planner output (by Fable) for [space-plan.md](space-plan.md) (all decisions locked 2026-07-18:
> CloudKit/CKShare, invite-link join, all-members-see-everything, iCloud identity, comment-style
> responses, trusted-group UI-level trust, raw CloudKit + isolated `SpaceStore` cache).
> Branch **`feature/space`** off `develop` — see Branch note at the bottom. All paths relative to
> the repo root. Format and conventions follow [insight-tasks.md](insight-tasks.md), which executor
> agents ran successfully.

## Ground-truth corrections (verified against `develop` @ `ede4e71`)

1. **`DIContainer.shared.configure(with:)` IS called** in `Reflect/ReflectApp.swift` `init` (line ~60)
   on this branch — unlike the insight worktree. Even so, **no Space factory may guard on the private
   `modelContext`**: Space never touches the main store. Follow the Insight factory pattern in
   `Reflect/App/DIContainer.swift` (`// MARK: - Insight`, lines 33–72): self-contained, `@MainActor`
   where a `mainContext` is involved.
2. **`Reflect/Info.plist` is a physical file** (currently only `CFBundleURLTypes`) merged with
   `GENERATE_INFOPLIST_FILE = YES` (pbxproj lines ~398/440). `CKSharingSupported` and
   `UIBackgroundModes` go **into that plist file directly — no `project.pbxproj` edit needed**.
   Verify after building that the merged product Info.plist contains both keys (see T1 acceptance).
3. **`Reflect/Reflect.entitlements` needs NO changes.** It already has `aps-environment`
   (development), iCloud container `iCloud.xyz.nandamochammad.Reflect`, CloudKit service, and the
   App Group. Space adds Info.plist keys only. Do not touch the entitlements file in any ticket.
4. **`Reflect/ReflectApp.swift` is pure SwiftUI lifecycle** — no App/Scene delegate exists anywhere.
   Share acceptance (`windowScene(_:userDidAcceptCloudKitShareWith:)`) and silent-push handling
   require a new `@UIApplicationDelegateAdaptor` + `UIWindowSceneDelegate` (T2).
5. **`MainTabView.swift`** (`Reflect/Presentation/Features/MainTab/MainTabView.swift`) is a real
   `TabView` with two `Tab` entries (Learnings, Insights), plus the onboarding `.sheet`, the
   celebration `.fullScreenCover` on `.badgesDidUnlock`, and `.onChange(of: widgetAction)` routing.
   The Spaces tab (T15) must preserve all of these exactly.
6. **`CloudSyncService` uses `CKContainer.default()`** (`Reflect/Services/Cloud/CloudSyncService.swift`
   line 6–10) and the private DB **default zone** with record types `CKLearning`/`CKReflection`/
   `CKImageAttachment`/`CKVoiceRecording`. `SpaceCloudService` must use
   `CKContainer(identifier: "iCloud.xyz.nandamochammad.Reflect")` explicitly, **custom zones only**,
   record types `Space`/`SpaceReflection`/`Response` — zero overlap, never modify `CloudSyncService`.
7. **pbxproj is `objectVersion = 77` with `PBXFileSystemSynchronizedRootGroup`** — new `.swift` files
   under `Reflect/` auto-join the app target. **No ticket edits `project.pbxproj`.** (If Xcode
   rewrites it during a human gate, reconcile that diff in the following review checkpoint.)
8. **Isolation template**: `Shared/Insight/InsightStore.swift` — dedicated `ModelContainer`, distinct
   store name, `cloudKitDatabase: .none`, tiered non-fatal fallback (App Group → local → in-memory).
   `SpaceStore` copies this but **does NOT need the App Group** (no widget/appex reads Space):
   local on-disk first, in-memory fallback.
9. **`Domain/Entities/` exists** (`Reflect/Domain/Entities/` — flat files like
   `CreateReflectionInput.swift`). Space entities go in a new `Reflect/Domain/Entities/Space/` folder.
10. **CKRecord-mapping precedent** to mirror: the `uploadLearning`/`uploadReflection` functions in
    `CloudSyncService.swift` (lines 278–323) — plain field-by-field `record["key"] = value` mapping.

## Hard isolation constraints (every ticket, every executor)

- **Never modify**: the main `Schema` in `ReflectApp.swift`, any file under `Reflect/Data/Models/`,
  `Shared/Insight/*`, `Reflect/Services/Cloud/CloudSyncService*`, existing repositories/use cases,
  or `Reflect/Reflect.entitlements`.
- **Grep gate before every commit**: `grep -rn "Learning\|Reflection(" <your new files>` must show no
  coupling to the personal-journal models (the word "Reflection" appears only inside
  `SpaceReflection`).
- Deleting `Reflect/**/Space*`, `Reflect/Services/Space/`, and the Spaces tab entry must return the
  app to today's state — keep it that way.

---

## Tickets

Legend — Executor: **Sonnet (main)** = CloudKit sharing/sync, delegate/config surgery, SwiftUI
composition, DI wiring. **Haiku (supporting)** = mechanical mirroring of an existing file.
**Human** = requires the user (portal/Console/hardware). IDs are dependency-ordered within phase.

---

### Phase P0 — sharing spike & plumbing (de-risk first, UI later)

### T1 — Info.plist config: `CKSharingSupported` + remote-notification background mode · Sonnet (main)
- **Scope**: Edit `Reflect/Info.plist` only. Add:
  (1) `CKSharingSupported` = `<true/>` (app advertises it accepts CloudKit share links);
  (2) `UIBackgroundModes` = array with `remote-notification` (silent pushes wake the app for sync).
  - **Out of scope**: entitlements (no changes needed — correction #3), pbxproj, any Swift,
    `registerForRemoteNotifications` (that call lands in T2's AppDelegate).
- **Depends on**: none
- **Acceptance**: `xcodebuild ... | grep "error:"` empty + `** BUILD SUCCEEDED **`; then verify the
  merged plist of the built product:
  `plutil -p <DerivedData>/.../Reflect.app/Info.plist | grep -A2 -E "CKSharingSupported|UIBackgroundModes"`
  shows both keys (proves the physical plist merged with the generated one). Committed.
- **Watch-outs**: Because `GENERATE_INFOPLIST_FILE = YES`, a typo'd key silently no-ops — the
  `plutil` check on the *built product* is the real gate, not the source file. Don't add
  `INFOPLIST_KEY_...` build settings; the plist file route avoids the pbxproj lock entirely.

### T2 — AppDelegate + SceneDelegate: share acceptance + remote-notification entry points · Sonnet (main)
- **Scope**: New file `Reflect/App/AppDelegate.swift` containing:
  - `final class AppDelegate: NSObject, UIApplicationDelegate` —
    `application(_:didFinishLaunchingWithOptions:)` calls
    `UIApplication.shared.registerForRemoteNotifications()` (silent pushes need no permission
    prompt); `application(_:configurationForConnecting:options:)` returns a
    `UISceneConfiguration` whose `delegateClass = SceneDelegate.self`;
    `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)` — for now, post
    `Notification.Name.spaceRemoteChangeReceived` and call the handler with `.newData`
    (T22 turns this into a real sync trigger).
  - `final class SceneDelegate: NSObject, UIWindowSceneDelegate` —
    `windowScene(_:userDidAcceptCloudKitShareWith metadata: CKShare.Metadata)` — for now, post
    `Notification.Name.spaceShareInviteReceived` with the metadata as object (T15 routes it;
    T5's spike harness observes it too).
  - Define the two `Notification.Name` statics in this file (house precedent: badge names live in
    `Domain/Notifications`; these are app-plumbing names, keep them beside the delegate).
  - Edit `Reflect/ReflectApp.swift`: add
    `@UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate` to `ReflectApp`.
    **Touch nothing else in that file** — not the `Schema`, not `handleWidgetURL`, not `init`.
  - **Out of scope**: `CKAcceptSharesOperation` (service concern, T4), any UI routing (T15),
    subscriptions (T22).
- **Depends on**: none (T1 not required to compile; both are wanted before T7's device test)
- **Acceptance**: Build green; app still launches to the existing two tabs on simulator (delegate
  adaptor must not break the SwiftUI scene); `ReflectApp.swift` diff is the one adaptor line only.
  Committed. **Two-device-only verification (deferred to T7/T16)**: acceptance callback actually
  firing on a real share link — cannot be simulated.
- **Watch-outs**: With a scene delegate class supplied via `configurationForConnecting`, SwiftUI
  still owns the window — do NOT create a `UIWindow` in `SceneDelegate` or the app goes black.
  If the accept callback never fires on device, the usual culprit is the missing
  `CKSharingSupported` key (T1) or the delegate class not being registered — check
  `scene(_:willConnectTo:)` logging first. Also implement
  `application(_:userDidAcceptCloudKitShareWith:)` on the AppDelegate as a belt-and-braces
  fallback (some launch paths deliver it there).

### T3 — Space domain entities (`Domain/Entities/Space/`) · Haiku (supporting)
- **Scope**: New folder `Reflect/Domain/Entities/Space/` with pure value types (no CloudKit import
  in the structs themselves; a `recordName: String` field carries identity):
  - `Space.swift` — `struct Space: Identifiable, Hashable, Sendable`: `id: String` (record name),
    `name: String`, `detail: String?`, `emoji: String?`, `isOwner: Bool`,
    `zoneID: SpaceZoneRef`, `createdAt: Date?`, `participantCount: Int`.
  - `SpaceZoneRef.swift` — `struct SpaceZoneRef: Hashable, Sendable`: `zoneName: String`,
    `ownerName: String`, `lane: SpaceLane`; `enum SpaceLane: Sendable { case privateDB, sharedDB }`
    (which CKDatabase a space lives in — owner vs joined).
  - `SpaceReflection.swift` — `struct SpaceReflection: Identifiable, Hashable, Sendable`:
    `id: String`, `spaceID: String`, `title: String`, `promptText: String`,
    `authorRecordName: String?`, `authorDisplayName: String?`, `createdAt: Date?`,
    `modifiedAt: Date?`, `isMine: Bool`.
  - `SpaceResponse.swift` — `struct SpaceResponse: Identifiable, Hashable, Sendable`: `id: String`,
    `reflectionID: String`, `body: String`, `authorRecordName: String?`,
    `authorDisplayName: String?`, `createdAt: Date?`, `isMine: Bool`.
  - `SpaceError.swift` — `enum SpaceError: Error, LocalizedError`: `iCloudUnavailable`,
    `nameRequired`, `nameTooLong`, `bodyRequired`, `bodyTooLong`, `notFound`, `notOwner`,
    `shareFailed(String)`, `acceptFailed(String)`, `syncFailed(String)`; user-facing
    `errorDescription` per case.
  - Add to `Reflect/Core/Utils/Constants.swift` (or wherever `Constants.Limits` lives — locate via
    `grep -rn "insightTextMaxLength"`): `spaceNameMaxLength = 50`,
    `spaceReflectionTitleMaxLength = 200`, `spaceResponseMaxLength = 5000` (plan §5 limits).
  - **Out of scope**: CKRecord mapping (T4), cache `@Model` classes (T8), use cases.
- **Depends on**: none
- **Acceptance**: Build green; no `import CloudKit`/`SwiftData` in the entity files; field names
  match plan §5 exactly; grep gate clean; committed.
- **Watch-outs**: Keep `Sendable` conformance real (all stored properties value types) — these
  structs cross actor boundaries in T4/T9. `SpaceLane` is the single source of truth for DB
  routing; don't let later tickets invent a second bool for it.

### T4 — `SpaceCloudService` core: container, zones, share, roots, accept · Sonnet (main)
- **Scope**: New folder `Reflect/Services/Space/` with:
  - `SpaceCloudServiceProtocol.swift` — protocol with async methods:
    `checkAvailability() async -> CloudAvailability` (mirror
    `CloudSyncService.checkCloudAvailability` semantics; reuse the existing `CloudAvailability`
    type — read-only reuse is fine),
    `createSpace(name:detail:emoji:) async throws -> (Space, CKShare)`,
    `fetchOwnedSpaces() async throws -> [Space]`,
    `fetchJoinedSpaces() async throws -> [Space]`,
    `fetchShare(for: SpaceZoneRef) async throws -> CKShare`,
    `acceptShare(metadata: CKShare.Metadata) async throws -> Space`,
    `deleteSpace(_ zone: SpaceZoneRef) async throws` (owner: `CKModifyRecordZonesOperation`
    delete on private DB),
    `leaveSpace(_ zone: SpaceZoneRef) async throws` (participant: delete the mirrored zone from
    the SHARED DB — removes only my access, plan §6.7).
  - `SpaceRecord.swift` — record-type constants (`"Space"`, `"SpaceReflection"`, `"Response"`),
    field-key constants, and `CKRecord ↔ entity` mapping functions mirroring the style of
    `CloudSyncService.uploadLearning` (plain `record["name"] = ...`; read `creatorUserRecordID`,
    `creationDate`, `modificationDate` from system metadata per plan §3/§5).
  - `SpaceCloudService.swift` — implementation. Non-negotiables:
    - `CKContainer(identifier: "iCloud.xyz.nandamochammad.Reflect")` **explicitly** (correction #6);
      hold `privateDB` and `sharedDB`; route every op by `SpaceZoneRef.lane`.
    - Create space = new custom zone `Space-<UUID>` in private DB, then save the root `Space`
      record **and** `CKShare(rootRecord:)` with `publicPermission = .none` in **one
      `CKModifyRecordsOperation`** (CloudKit requires root+share atomic — plan §6.1).
    - Owned spaces: fetch space zones from private DB → each zone's root record. Joined:
      `fetchAllRecordZones` on shared DB → each zone's root. Tag `isOwner`/lane accordingly.
    - Accept: `CKAcceptSharesOperation` from `CKShare.Metadata`, then fetch the root record from
      the shared DB and return the `Space`.
    - Copy the retry helper shape from `CloudSyncService.uploadWithRetry` (exponential backoff)
      rather than inventing new machinery.
  - **P0 decision point (record in code comment + T7 outcome)**: this ticket implements the
    **manual-operations path**. `CKSyncEngine` is evaluated at T22 for the *sync loop* only —
    creation/share/accept are explicit operations either way, so this core is not throwaway.
  - **Out of scope**: `SpaceReflection`/`Response` CRUD (T17), participant management UI hooks
    (UICloudSharingController owns that, T12), subscriptions (T22), any caching (T9).
- **Depends on**: T3
- **Acceptance**: Build green; protocol + impl compile with zero references to
  Learning/Reflection/InsightStore/`CKContainer.default()`; every method routes DB by lane;
  root+share saved in a single operation (visible in code); committed.
  **Two-device-only verification (T7)**: share link round trip, shared-DB zone appearance,
  accept flow — none of this is provable on simulator.
- **Watch-outs**: (1) Root+share **must** be in the same `CKModifyRecordsOperation` or CloudKit
  rejects the share. (2) The shared DB has no "my zones" concept — zone IDs carry the OWNER's
  name; never construct shared-DB zone IDs with `CKCurrentUserDefaultName`. (3) `leaveSpace` zone
  delete targets the **shared** DB (participant) vs `deleteSpace` targeting the **private** DB
  (owner) — getting these crossed destroys the space for everyone; assert on `lane` at the top of
  each. (4) `records(matching:)` queries don't work on the shared DB the way they do in private
  default zones — enumerate zones + fetch by record ID instead. (5) Eventual consistency: a
  just-created zone may not appear in an immediate re-fetch; do not "fix" that with sleeps in the
  service — the cache layer (T9) absorbs it.

### T5 — DEBUG-only spike harness screen · Sonnet (main)
- **Scope**: New file `Reflect/Presentation/Features/Settings/SpaceDebugView.swift` (or a new
  `Reflect/Presentation/Features/Space/Debug/` folder), fully wrapped in `#if DEBUG`:
  a plain list of buttons driving `SpaceCloudService` directly (no repository, no cache):
  create test space → show share sheet for its `CKShare` (minimal `UICloudSharingController`
  inline wrapper is acceptable here, throwaway), list owned zones, list joined zones, write a
  probe `SpaceReflection` child record into a chosen space (inline one-off save using
  `SpaceRecord` mapping — T17 does it properly later), fetch + dump a zone's records to a
  scrollable text area, observe `spaceShareInviteReceived` and call
  `service.acceptShare(metadata:)`. Add a `#if DEBUG` row in the Settings screen
  (locate: `grep -rn "SettingsView" Reflect/Presentation/Features/Settings/`) to push it.
  - **Out of scope**: anything shipping — this screen is deleted/kept-DEBUG forever; no DIContainer
    factory (instantiate the service directly here).
- **Depends on**: T2 (accept notification), T4
- **Acceptance**: Build green (Debug config); harness screen reachable in simulator; create-space
  button produces a zone visible in CloudKit Console Development env (agent can verify Console
  only if the user shares a screenshot — otherwise this is part of gate T7). Committed.
- **Watch-outs**: Keep every symbol `#if DEBUG`-fenced including the Settings row, so Release
  builds are byte-identical on this surface. The share sheet requires a real `CKShare` already
  saved — present it only after `createSpace` returns.

### T6 — HUMAN GATE H1: Developer portal + CloudKit Console setup · Human
- **Scope**: Human-only, in parallel with T1–T5:
  1. **Developer portal / Xcode Signing & Capabilities**: confirm the App ID for
     `xyz.nandamochammad.Reflect` has **Push Notifications** enabled (the `aps-environment`
     entitlement already exists, but the portal capability must be on for device builds to sign
     and for APNs to deliver CloudKit silent pushes). Add it if missing; regenerate profiles.
  2. **CloudKit Console** (icloud.developer.apple.com → container
     `iCloud.xyz.nandamochammad.Reflect` → **Development** environment): confirm the three record
     types `Space`, `SpaceReflection`, `Response` exist after T5's first writes (Development
     auto-creates them on first save; if the team prefers, define them manually first per plan §5),
     and add any needed queryable indexes (`recordName` queryable on all three is the safe default).
  3. Have a **second iCloud account** signed in on a **second physical device** (or the user's Mac)
     with the app installed via Xcode — required for T7 and every later two-device gate.
- **Depends on**: nothing to *start*; item 2 is easiest after T5 exists.
- **Acceptance**: Push capability visible on the App ID; record types visible in Console
  Development; two devices with two iCloud accounts ready. The human replies "H1 done" to the
  orchestrator.
- **Watch-outs**: If Xcode's capability UI rewrites `project.pbxproj` or the entitlements file,
  **capture that diff and hand it to the next review checkpoint** — agents must not blindly
  overwrite it. Console schema work here is Development-only; Production deploy is T24, much later.

### T7 — HUMAN GATE H2: two-device spike round trip (P0 exit criterion) · Human (agent assists)
- **Scope**: Using T5's harness on two physical devices / two iCloud accounts:
  Device A creates a space → sends the invite link via Messages → Device B taps the link → app
  opens, accept fires (`userDidAcceptCloudKitShareWith`), zone appears in B's shared DB →
  B writes the probe child record → A re-fetches and sees B's record (pull; push comes in T22).
  Record the outcome (works / broken where) in a short addendum committed to
  `docs/features/space-plan.md` §12 T0.2, including the confirmed **manual-operations decision**
  (or an escalation if `CKSyncEngine` must be reconsidered).
- **Depends on**: T1, T2, T4, T5, T6
- **Acceptance**: **Round trip proven end-to-end on hardware** — this is the P0 exit criterion
  (plan §12) and retires the feature's majority risk. Outcome addendum committed.
- **Watch-outs**: If the link opens the iCloud web page instead of the app: T1's key missing from
  the built product, or the app not installed from the same team/bundle on device B. Give the
  shared DB up to a minute after accept (eventual consistency) before declaring failure.
  **Nothing in P1/P2 UI work should merge past review checkpoint R2 until H2 passes.**

---

### Phase P1 — create / join / list spaces

### T8 — `SpaceStore` isolated cache (InsightStore pattern) · Haiku (supporting)
- **Scope**: New folder `Reflect/Data/Space/`:
  - `SpaceStore.swift` — `enum SpaceStore` mirroring `Shared/Insight/InsightStore.swift`
    line-for-line in structure: `static let container: ModelContainer` built from
    `Schema([CachedSpace.self, CachedSpaceReflection.self, CachedSpaceResponse.self])`, store name
    `"Space"`, `groupContainer: .none` (no widget needs it — correction #8),
    `cloudKitDatabase: .none` (**the cache itself must never sync — CloudKit is upstream**),
    tiered fallback local on-disk → in-memory with the same `print` warnings, `try!` only on the
    in-memory tier with the same justification comment.
  - `CachedSpace.swift`, `CachedSpaceReflection.swift`, `CachedSpaceResponse.swift` —
    `@preconcurrency @Model final class` each, mirroring `Shared/Insight/Insight.swift` style:
    `@Attribute(.unique) var id: String` (CKRecord name), the fields from T3's entities flattened
    to scalars (`laneRawValue: String` etc.), `zoneName`/`ownerName` on `CachedSpace`,
    `spaceID` on reflections, `reflectionID` on responses (**string keys, no SwiftData
    relationships** — server is the system of record, plan §4), `lastFetchedAt: Date`; memberwise
    inits; converters `init(from: Space)` / `func toDomain() -> Space` (and likewise for the
    other two).
  - **Out of scope**: any fetch/upsert logic (repository, T9); anything under `Shared/`.
- **Depends on**: T3 (field parity)
- **Acceptance**: Build green; `SpaceStore` never referenced from `ReflectApp`'s schema or
  `InsightStore`; zero relationships between the three `@Model`s; grep gate clean; committed.
- **Watch-outs**: Distinct store name `"Space"` so it can never collide with `default.store` or
  `Insight.store`. Do not add the models to any other container's schema.

### T9 — `SpaceRepository`: cloud-through cache orchestration · Sonnet (main)
- **Scope**:
  - `Reflect/Data/Repositories/Protocols/SpaceRepositoryProtocol.swift` — async methods:
    `fetchSpaces(forceRefresh: Bool) async throws -> [Space]` (merged owned+joined),
    `createSpace(name:detail:emoji:) async throws -> Space`,
    `shareForSpace(_:) async throws -> CKShare`, `acceptInvite(metadata:) async throws -> Space`,
    `deleteSpace(_:) async throws`, `leaveSpace(_:) async throws`,
    `cachedSpaces() -> [Space]` (synchronous cache read for instant first paint).
  - `Reflect/Data/Repositories/Implementations/SpaceRepository.swift` —
    `init(cloudService: SpaceCloudServiceProtocol, modelContext: ModelContext)` (the context comes
    from `SpaceStore.container.mainContext` via DIContainer, T11). Read path: return cache
    immediately, refresh from cloud, upsert by `id` (insert/update/delete-stale for the fetched
    scope), save. Write path: cloud first, then upsert cache on success — **the cache never leads**.
  - **Out of scope**: reflections/responses methods (T17 extends this same pair — note for the
    file lock), any UI, subscriptions.
- **Depends on**: T4, T8
- **Acceptance**: Build green; every mutation calls the cloud service before touching the cache;
  upsert is by unique `id` (no duplicate rows across refreshes); errors propagate as `SpaceError`
  (no silent `try?`); grep gate clean; committed.
- **Watch-outs**: Delete-stale must be scoped (only spaces, only within the refreshed lane) so a
  transient partial fetch doesn't wipe the cache. `mainContext` is `@MainActor` — mark the
  repository `@MainActor` (matches how Insight factories are wired) and keep the cloud calls
  `await`ed off the context work.

### T10 — Space use cases (Create / Fetch / Delete / Leave / AcceptInvite) · Haiku (supporting)
- **Scope**: New folder `Reflect/Domain/UseCases/Space/`, one file per class, mirroring the
  Insight use-case shape (protocol + `execute(...) async throws`):
  `CreateSpaceUseCase` (validates `SpaceError.nameRequired` / `.nameTooLong` against
  `Constants.Limits.spaceNameMaxLength` before calling the repository), `FetchSpacesUseCase`
  (passthrough with `forceRefresh`), `DeleteSpaceUseCase` (guards `isOwner == true` else
  `SpaceError.notOwner`), `LeaveSpaceUseCase` (guards `isOwner == false`),
  `AcceptSpaceInviteUseCase` (metadata → repository).
  - **Out of scope**: reflection/response use cases (T18), DIContainer edits (T11).
- **Depends on**: T9
- **Acceptance**: Build green; naming matches house `<Verb><Entity>UseCase`; validation lives here
  (not in ViewModels); grep gate clean; committed.
- **Watch-outs**: `Delete` vs `Leave` owner-guards are the last line of defense before the
  destructive service paths (T4 watch-out #3) — do not skip them as "the UI already checks".

### T11 — DIContainer Space factories · Haiku (supporting)
- **Scope**: Additive `// MARK: - Space` section in `Reflect/App/DIContainer.swift`, modeled on the
  Insight section (lines 33–72): `makeSpaceCloudService() -> SpaceCloudServiceProtocol`
  (plain init), `@MainActor makeSpaceRepository()` wired to `SpaceStore.container.mainContext`,
  and `@MainActor` factories for the five T10 use cases. **Never guard on the private
  `modelContext`** (correction #1). ViewModel factories are added by the UI tickets that own the
  VMs (T13/T14/T20/T21) — this ticket stops at use cases.
- **Depends on**: T10
- **Acceptance**: Build green; no Space factory can hit the `configure` fatalError; existing
  factories byte-identical; committed.
- **Watch-outs**: `DIContainer.swift` is a locked file — this ticket and later VM-factory additions
  (T13→T14→T20→T21) must run strictly serially on it.

### T12 — `UICloudSharingController` SwiftUI wrapper · Sonnet (main)
- **Scope**: New file `Reflect/Presentation/Features/Space/Share/CloudSharingView.swift`:
  `struct CloudSharingView: UIViewControllerRepresentable` taking `share: CKShare`,
  `container: CKContainer`, and a `spaceName: String`. Coordinator implements
  `UICloudSharingControllerDelegate`: `itemTitle` → space name,
  `cloudSharingController(_:failedToSaveShareWithError:)` → surface via a bound optional error,
  `cloudSharingControllerDidSaveShare` / `DidStopSharing` → callbacks the presenting VM can hook.
  Set `availablePermissions = [.allowReadWrite, .allowPrivate]` (invite-only, read-write — plan
  locked decisions #4/#7). This wrapper is also the owner-side participant-management and
  stop-sharing UI for free (plan §6.2/§6.8) — no separate participant screen in MVP.
  - **Out of scope**: creating the share (T4 already saved it), any list/form UI.
- **Depends on**: T3 (only for types in callbacks; effectively parallel-safe after T4)
- **Acceptance**: Build green; wrapper compiles with the delegate wired; presenting it in T5's
  debug harness (optional swap-in) shows the system share sheet on device. Committed.
  **Two-device-only**: actually sending/accepting the link (covered by T16/H3).
- **Watch-outs**: `UICloudSharingController(share:container:)` requires the share to exist on the
  server already — never construct with the "prepare handler" variant here (that path creates
  shares lazily and would bypass T4's atomic create). Dismissal is delegate-driven; don't wrap it
  in a `.sheet` you also dismiss manually or the controller's save can be cancelled mid-flight.

### T13 — Create-space flow (form + invite hand-off) · Sonnet (main)
- **Scope**: New folder `Reflect/Presentation/Features/Space/Form/`:
  - `SpaceFormViewModel.swift` — `@Observable @MainActor final class`, MARK sections per house
    style: `name`, `detail`, `emoji`, `canSave`, `isSaving`, `createdShare: CKShare?`,
    `save() async -> Space?` via `CreateSpaceUseCase` + `shareForSpace` (haptics on success,
    `HapticManager` precedent).
  - `SpaceFormView.swift` — sheet with name field (counter vs 50), optional detail + emoji,
    Create button; on success immediately presents `CloudSharingView` (T12) so create → invite is
    one continuous flow (plan §6.1–6.2).
  - Add `@MainActor func makeSpaceFormViewModel()` to `DIContainer.swift` (**lock**: runs after
    T11, before T14's factory).
  - **Out of scope**: the list that presents this sheet (T14), tab wiring (T15).
- **Depends on**: T11, T12
- **Acceptance**: Build green; save goes exclusively through the use case (no service or
  `modelContext` access in the view/VM); create-then-share presents the sharing controller with
  the fresh share; committed. **Two-device-only**: link delivery/acceptance (H3).
- **Watch-outs**: `CKShare` is not `Sendable`-friendly across arbitrary hops — keep it inside the
  `@MainActor` VM. Handle `SpaceError.iCloudUnavailable` with an inline message, not a crash.

### T14 — Spaces list slice (owned + joined, leave/delete, states) · Sonnet (main)
- **Scope**: New folder `Reflect/Presentation/Features/Space/List/`:
  - `SpaceListViewModel.swift` — `@Observable @MainActor`: `spaces: [Space]`,
    `availability: CloudAvailability`, `isRefreshing`, `load()` (cache-first paint via
    `cachedSpaces()`, then `fetchSpaces(forceRefresh:)`), `delete(_:)` / `leave(_:)` via use
    cases, `errorMessage`.
  - `SpaceRowView.swift` — emoji/name/detail, owner badge ("Owner" tag) vs joined, participant
    count.
  - `SpaceListView.swift` — `NavigationStack`; toolbar `+` presenting `SpaceFormView`; list with
    swipe actions — **owner rows get Delete** (confirmation dialog: "Deletes this space and all
    its content for every member. This cannot be undone.") and **joined rows get Leave**
    (dialog: "You'll lose access. The space and its content remain for other members.") — the
    plan §11.3 copy distinction is a requirement, not polish; pull-to-refresh; empty state via
    the existing `EmptyStateView` component; **iCloud-unavailable state** ("Sign in to iCloud in
    Settings…") when `availability != .available` (plan §11.7 — this ticket includes plan task
    T1.5); generic error banner otherwise.
  - Add `@MainActor func makeSpaceListViewModel()` to `DIContainer.swift` (**lock**: after T13's
    factory).
  - Navigation destination to the space detail is a placeholder `Text` until T20 replaces it —
    keep the `NavigationLink(value:)` typed on `Space` now.
  - **Out of scope**: MainTabView wiring (T15), space detail (T20).
- **Depends on**: T11, T13 (DIContainer serial order + presents T13's form)
- **Acceptance**: Build green; list renders from cache without network on simulator (empty is
  fine); owner/joined rows offer the correct destructive action with the correct copy; all
  mutations via use cases; committed. **Two-device-only**: joined spaces actually appearing (H3).
- **Watch-outs**: Both dialogs are destructive-confirm (`role: .destructive`); never offer Delete
  on a joined row (T10's guard would throw, but the row must not show it). Cache-first paint then
  refresh — no spinner-blocking the whole list.

### T15 — Spaces tab + accept-invite routing (shared surfaces) · Sonnet (main)
- **Scope**: The only P1 ticket touching `MainTabView.swift`:
  - `Reflect/Presentation/Features/MainTab/MainTabView.swift` — add `case spaces` to `MainTab`;
    add a third `Tab("Spaces", systemImage: "person.3.fill", value: .spaces)` hosting
    `SpaceListView()`. **Do NOT** attach `InsightStore.container` or the main container to it —
    Space views get their data via ViewModels, not `@Query`, so no `.modelContainer` injection is
    needed on this tab. Preserve untouched: onboarding sheet, celebration cover,
    `.onChange(of: widgetAction)` routing (Space has no widget action in MVP — do not extend
    `WidgetAction`).
  - Accept routing: observe `spaceShareInviteReceived` (from T2's SceneDelegate) in `MainTabView`
    — on receipt: switch to `.spaces`, call `AcceptSpaceInviteUseCase` (via a small
    `@Observable` router or directly in the view's `.onReceive` + `Task`), then navigate into
    the joined space (append to `SpaceListView`'s navigation path via a binding or a
    pending-space signal, mirroring the existing `insightComposeSignal` pattern), per plan §6.3.
  - **Out of scope**: `ReflectApp.swift` (T2 already finished it), any Space view internals.
- **Depends on**: T2, T14
- **Acceptance**: Build green; three tabs; Learnings + Insights behavior byte-identical (widget
  deep links `reflect://write|camera|voice|insight` still route correctly via
  `xcrun simctl openurl`); simulator shows the Spaces tab with empty/signed-out states.
  Committed. **Two-device-only (H3)**: tapping a real invite link lands inside the joined space.
- **Watch-outs**: This is the highest-regression-risk shared surface in P1 — the checkpoint R3
  review below is mandatory before P2 fans out. The accept notification can arrive while
  onboarding or the celebration cover is up; queue the pending metadata (`@State`) and act when
  the cover is down rather than fighting the presentation stack.

### T16 — HUMAN GATE H3: two-device P1 verification · Human (agent assists)
- **Scope**: On the two H1 devices, through the real UI (debug harness not allowed): create a
  space on A → invite via the form's share sheet → B taps link → B lands in the joined space →
  both see it in their lists (A "Owner", B joined) → B leaves → B's list empties, A's space
  survives → re-invite B → A removes B via the sharing controller's participant UI → B loses
  access on next refresh → A deletes the space → gone for both. File any breakage as findings for
  the R3 checkpoint; agent fixes ≤10-line issues inline, escalates the rest.
- **Depends on**: T7 (H2 passed), T13, T14, T15
- **Acceptance**: All eight steps pass on hardware; results noted in the PR/commit description.
- **Watch-outs**: Removed-participant and left-participant states can take a sync cycle to
  propagate — pull-to-refresh before judging. This gate must pass before T24 (TestFlight).

---

### Phase P2 — reflections, responses, push

### T17 — Extend service + repository with `SpaceReflection`/`Response` CRUD · Sonnet (main)
- **Scope**: Extends four existing files (**locks**: `SpaceCloudServiceProtocol.swift`,
  `SpaceCloudService.swift`, `SpaceRepositoryProtocol.swift`, `SpaceRepository.swift` — no other
  ticket may touch them concurrently):
  - Service: `fetchReflections(in: SpaceZoneRef) async throws -> [SpaceReflection]`,
    `createReflection(in:title:promptText:) async throws -> SpaceReflection`,
    `fetchResponses(for reflection: SpaceReflection, in: SpaceZoneRef) async throws -> [SpaceResponse]`,
    `createResponse(to:body:in:) async throws -> SpaceResponse`,
    `deleteRecord(id:in:) async throws` (own-content delete; UI-level trust, plan locked #7).
    Children set `record.parent` to their parent record (root for reflections, reflection for
    responses — plan §3, non-negotiable: parent references carry the share). Writes route by
    lane: owner → private DB zone, member → mirrored shared-DB zone (plan §6.5).
  - **Author resolution**: fetch the zone's `CKShare` participants once per sync
    (`fetchShare(for:)` from T4), map `creatorUserRecordID` →
    `participant.userIdentity.nameComponents` (formatted), fall back to `"A member"` when nil
    (plan §3). Set `isMine` by comparing against
    `CKContainer.userRecordID(forCurrentUser)` — cache that ID once in the service.
  - Repository: mirror the five methods, cache-through to `CachedSpaceReflection`/
    `CachedSpaceResponse` with the same upsert discipline as T9, plus synchronous
    `cachedReflections(spaceID:)` / `cachedResponses(reflectionID:)`.
  - **Out of scope**: use cases (T18), any UI, subscriptions (T22), editing existing
    records (MVP is append-only + delete-own).
- **Depends on**: T9 (and H2 passed — R2)
- **Acceptance**: Build green; every child save sets `parent`; DB routing by lane in every new
  method; author fallback string present; grep gate clean; committed.
  **Two-device-only (T24)**: cross-member visibility of children and correct author names.
- **Watch-outs**: In the shared DB, fetch children via zone-change/zone-record fetches, not
  `CKQuery` against the default zone (T4 watch-out #4 applies doubly here). The owner's own
  record ID from `userRecordID` is `_defaultOwner`-style opaque — compare record names, not
  display names. Deleting a reflection must also delete its responses locally in cache (CloudKit
  cascades via parent on the server, the cache must not orphan rows).

### T18 — Space reflection/response use cases + DI factories · Haiku (supporting)
- **Scope**: In `Reflect/Domain/UseCases/Space/`: `CreateSpaceReflectionUseCase` (validates
  title 1..200 / prompt non-empty), `FetchSpaceReflectionsUseCase`,
  `CreateSpaceResponseUseCase` (body 1..5000 → `SpaceError.bodyRequired`/`.bodyTooLong`),
  `FetchSpaceResponsesUseCase`, `DeleteOwnSpaceContentUseCase` (guards `isMine == true` before
  calling repository delete — the UI-level trust boundary, plan §11.2). Add their `@MainActor`
  factories to `DIContainer.swift` under the existing `// MARK: - Space` (**lock**: serial after
  T14's factory, before T20/T21 factories).
- **Depends on**: T17
- **Acceptance**: Build green; validation + `isMine` guard in use cases, not views; committed.
- **Watch-outs**: The `isMine` guard is the ONLY thing standing between the UI and editing others'
  records (no server enforcement) — treat a missing guard as a review-blocking defect.

### T19 — UGC compliance: report action, first-use terms sheet, review notes · Haiku (supporting)
- **Scope** (plan §10):
  - `Reflect/Presentation/Features/Space/Compliance/SpaceTermsSheet.swift` — one-time sheet before
    first Space use ("no tolerance for objectionable content" acknowledgment), gated by a
    `Constants.UserDefaults.hasAcceptedSpaceTerms` bool; presented from `SpaceListView` on first
    appear (coordinate with T14's file via the lock table — this ticket edits `SpaceListView`
    only to add the `.sheet` + gate, nothing else).
  - `Reflect/Presentation/Features/Space/Compliance/ReportContentButton.swift` — a reusable
    context-menu/button that opens `mailto:` to the developer with subject/body pre-filled
    (space name, record ID, reporter). T20/T21 attach it to reflection rows and response rows.
  - `docs/features/space-appreview-notes.md` — short doc: UGC mechanisms (report, owner-delete,
    leave/remove), demo instructions for the reviewer.
  - **Out of scope**: any moderation backend (none exists by design).
- **Depends on**: T14 (touches `SpaceListView`); ReportContentButton itself only needs T3.
- **Acceptance**: Build green; terms sheet shows exactly once (UserDefaults-gated); report button
  produces a well-formed `mailto:` URL; notes doc committed.
- **Watch-outs**: `SpaceListView.swift` lock — run after T14 and not concurrently with T20/T21 if
  they also touch it (they shouldn't; they own Detail/Thread files).

### T20 — Space detail: reflections list + compose · Sonnet (main)
- **Scope**: New folder `Reflect/Presentation/Features/Space/Detail/`:
  - `SpaceDetailViewModel.swift` — `@Observable @MainActor`: cache-first `load()`, refresh,
    `reflections: [SpaceReflection]`, compose state, `deleteOwn(_:)`.
  - `SpaceDetailView.swift` — replaces T14's placeholder destination: reflection rows
    (title, author name, relative date, `isMine` marker), pull-to-refresh, `+` compose sheet
    (title + prompt text fields with counters), swipe-delete **only on `isMine` rows**, report
    button (T19) on every row, empty state. Sync-on-appear (plan §9: fetch makes it correct).
  - Add `@MainActor func makeSpaceDetailViewModel(space:)` to `DIContainer.swift` (**lock**:
    after T18).
  - **Out of scope**: response thread (T21) — row tap navigates to a typed destination T21 fills.
- **Depends on**: T18 (+ edits the `NavigationLink` destination created in T14)
- **Acceptance**: Build green; compose via use case; delete offered only on own rows; author names
  render with the "A member" fallback; committed. **Two-device-only (T24)**: seeing another
  member's reflection.
- **Watch-outs**: `SpaceListView.swift` is touched only to swap the placeholder destination —
  keep that diff to the one `navigationDestination` body (lock order with T19 noted above).

### T21 — Response thread UI (comment-style) + authorship · Sonnet (main)
- **Scope**: New folder `Reflect/Presentation/Features/Space/Thread/`:
  - `SpaceThreadViewModel.swift` — cache-first responses for one reflection, refresh,
    `postResponse(body:)` (multiple responses per member allowed — locked decision #6),
    `deleteOwn(_:)`.
  - `SpaceThreadView.swift` — reflection header (title/prompt/author), chronological responses
    (author name, relative date, `isMine` styling), always-visible composer bar (counter vs
    5000), delete-own via context menu, report button (T19) per response, sync-on-appear +
    pull-to-refresh.
  - Add `@MainActor func makeSpaceThreadViewModel(reflection:space:)` to `DIContainer.swift`
    (**lock**: after T20).
  - **Out of scope**: reactions, editing responses, push (T22).
- **Depends on**: T20
- **Acceptance**: Build green; posting appends via use case and re-renders; own vs others'
  affordances correct; committed. **Two-device-only (T24)**: cross-member thread updates.
- **Watch-outs**: After posting, insert the returned response into local state immediately
  (optimistic-after-server-ack) — waiting for a full refetch makes the composer feel dead under
  CloudKit latency (plan §11.4: design for "recently synced", not realtime chat).

### T22 — Database subscriptions + silent-push sync loop · Sonnet (main)
- **Scope**:
  - Service (**re-acquires the T17 file locks**): `ensureSubscriptions() async throws` — one
    `CKDatabaseSubscription` on the **private** DB and one on the **shared** DB, both with
    `notificationInfo.shouldSendContentAvailable = true`, idempotent (fixed subscription IDs,
    tolerate "already exists"); `syncChanges() async throws` —
    `CKFetchDatabaseChangesOperation` (changed zone IDs, per-DB stored change token) →
    `CKFetchRecordZoneChangesOperation` per changed zone (per-zone tokens) → upsert into
    `SpaceStore` via the repository; tokens persisted in `UserDefaults`
    (`Constants.UserDefaults.spacePrivateDBToken` etc.), reset-on-`CKError.changeTokenExpired`.
    **Decision hook**: if the T7 addendum recommended `CKSyncEngine`, implement this ticket with
    `CKSyncEngine` instead (it owns tokens/subscriptions/account changes) — same public surface
    (`ensureSubscriptions` becomes a no-op, `syncChanges` delegates to the engine).
  - `Reflect/App/AppDelegate.swift` (**lock**: only ticket after T2 to touch it):
    `didReceiveRemoteNotification` now triggers `syncChanges()` and completes with
    `.newData`/`.noData` accordingly.
  - Wire "fetch makes it correct" (plan §9): SpaceList/Detail/Thread VMs already sync on appear +
    pull-to-refresh (T14/T20/T21); add an app-foreground (`scenePhase == .active` while a Space
    screen is visible) refresh trigger via the `spaceRemoteChangeReceived` notification the VMs
    observe.
  - Conflict handling: on `serverRecordChanged` during saves, last-writer-wins on whole fields
    (plan §9) — retry once with the server record as base.
  - **Out of scope**: user-visible notifications (post-MVP), badge triggers (never in MVP).
- **Depends on**: T17 (service files), T2 (AppDelegate); benefits from T20/T21 existing but must
  not edit their files (VMs observe the notification added here — if a one-line `.onReceive` is
  needed in those views, coordinate via lock order: run T22 after T21).
- **Acceptance**: Build green; subscriptions idempotent across launches (log evidence);
  change-token persistence survives relaunch (simulator-checkable: tokens present in
  UserDefaults); foreground refresh path works on simulator against own private DB. Committed.
  **Two-device-only (T24)**: actual silent-push delivery A→B (simulators do not reliably receive
  CloudKit pushes — plan §11.5; this is the headline hardware-only item).
- **Watch-outs**: Silent pushes are throttled/coalesced — never let correctness depend on them
  (the appear/foreground/pull fetches are the guarantee). Do not subscribe with query/zone
  subscriptions in the shared DB (unsupported/unreliable) — database subscriptions only.
  `changeTokenExpired` must clear the token and refetch from scratch, not crash. Keep every new
  UserDefaults key namespaced `space...` to avoid colliding with sync-backup keys.

### T23 — HUMAN GATE H4: CloudKit Console — deploy schema to Production · Human
- **Scope**: CloudKit Console → container `iCloud.xyz.nandamochammad.Reflect` → **Deploy Schema
  Changes** from Development to **Production** (the three record types + indexes + subscription
  types). Per plan §8 this is a classic release-blocking footgun — **TestFlight builds talk to
  Production and will find zero record types without this step.**
- **Depends on**: T17, T22 (schema final — no record-type/field changes after this without
  re-deploying)
- **Acceptance**: Production environment shows `Space`, `SpaceReflection`, `Response` with the
  same fields/indexes as Development. Human replies "H4 done".
- **Watch-outs**: Production schema is append-only (fields can't be deleted) — that's why this
  gate sits after all record-shape tickets. If any P2 fix later adds a field, H4 must be repeated
  before the next TestFlight build.

### T24 — HUMAN GATE H5: TestFlight two-device end-to-end (P2 exit) · Human (agent assists)
- **Scope**: TestFlight build to ≥2 external testers (plan §12 T2.5). Full pass: invite link →
  install → accept (the plan §11.1 cold-install path — judge the UX, don't just test the happy
  path) → reflections + responses cross-device → **silent-push latency observed** (A posts, B
  backgrounded, B's next foreground shows it without manual refresh; also confirm pull-to-refresh
  correctness when push never arrives) → report/terms/leave/remove/delete re-verified on the
  Production environment.
- **Depends on**: T16 (H3), T19, T20, T21, T22, T23 (H4)
- **Acceptance**: All flows pass against **Production**; findings filed to the R5 checkpoint.
- **Watch-outs**: `aps-environment` flips to `production` automatically in TestFlight builds —
  device-build push tests before this used the development APNs environment; do not assume push
  behavior transfers.

### T25 — Final verification, decoupling audit, polish · Sonnet (main)
- **Scope**: The T12-style closing gate (mirror `insight-tasks.md` T12):
  - Build green (`xcodebuild ... grep "error:"` empty + `** BUILD SUCCEEDED **`).
  - Simulator regression pass: Learnings + Insights flows unchanged (incl.
    `xcrun simctl openurl reflect://write|camera|voice|insight`), onboarding, celebration cover;
    Spaces tab renders empty/signed-out states cleanly.
  - **Decoupling audit**: main `Schema` in `ReflectApp.swift` diff-clean vs `develop`;
    `grep -rn "Space" Reflect/Data/Models Shared/Insight Reflect/Services/Cloud` → zero hits;
    `grep -rn "CKContainer.default" Reflect/Services/Space` → zero hits;
    `grep -rn "InsightStore\|Learning\b" <all Space files>` → zero hits;
    `Reflect/Reflect.entitlements` diff-clean; `project.pbxproj` diff contains only human-gate
    fallout already reconciled at checkpoints.
  - Delete-test (dry): confirm removing `Reflect/**/Space*` folders + the tab entry would compile
    the rest (inspection, not an actual delete commit).
  - Fix ≤10-line issues inline; escalate structural gaps to the planner (Fable) with evidence.
- **Depends on**: T15, T19, T21, T22 (T24 findings folded in when available)
- **Acceptance**: All checks pass with pasted evidence; per-ticket commits exist on
  `feature/space`; **no push** (user pushes/PRs per repo rules).
- **Watch-outs**: iCloud-Drive repo gotcha (MEMORY): a build error in an untracked, unrelated file
  is likely stray iCloud WIP — check `git status` before chasing it.

---

## Execution waves — maximize parallelism where safe

Tickets in the same cell run **in parallel** (different agents, disjoint files). `→` = serial.
The whole point of this table: only 5 of 20 agent tickets are forced solo; everything else fans out.

| Wave | Parallel lanes | Serial/solo constraints | Human in parallel |
|---|---|---|---|
| 1 | **T1** ∥ **T2** ∥ **T3** ∥ **T8**\* | Disjoint files (Info.plist / new AppDelegate+one-line ReflectApp / new entity folder / new cache folder). \*T8 needs T3's field list — give the T8 agent T3's ticket text; true file conflicts: none. Safer default: start T8 when T3 commits. | **T6 (H1)** starts now: portal check + second device prep. |
| 2 | **T4** → **T5**; **T12** in parallel with T4/T5 | T4/T5 one lane (T5 uses T4). T12 only needs CloudKit types — separate lane. | H1 finishes; Console record-type check after T5's first device write. |
| 3 | — (hardware) | **T7 (H2) — P0 exit gate.** Agents may *build* Wave-4 tickets during the wait, but nothing merges past **R2** until H2 passes. | **T7 (H2)** two-device spike. |
| 4 | **T9** → **T10** → **T11** | Single lane (repo → use cases → DI). No parallel partner: everything else in P1 depends on T11. | — |
| 5 | **T13** → **T14** | Serial: both add a `DIContainer` factory and T14 presents T13's form. | — |
| 6 | **T15** solo | Only ticket touching `MainTabView.swift`. | — |
| 7 | **T17** (service/repo lock) ∥ **T19** (compliance components; its one-line `SpaceListView` edit waits for the R3 check) | T17 and T19 touch disjoint files apart from that. | **T16 (H3)** two-device P1 verification runs against the Wave-6 build. |
| 8 | **T18** → **T20** → **T21** → **T22** | Single lane: DIContainer lock (T18/T20/T21) then T22 re-locks service files + AppDelegate and adds the `.onReceive` the VMs observe. | — |
| 9 | — | **T23 (H4)** schema → Production, then **T24 (H5)** TestFlight E2E. | Both human gates. |
| 10 | **T25** solo | Final audit + T24 findings. | — |

## Shared-file locks (orchestrator MUST enforce — one ticket at a time, in this order)

| File | Serial order (only these tickets may touch it) |
|---|---|
| `Reflect/Info.plist` | **T1 only** |
| `Reflect/Reflect.entitlements` | **NO ticket** — any diff here is human-gate fallout; reconcile at the next checkpoint |
| `Reflect.xcodeproj/project.pbxproj` | **NO ticket** — filesystem-synchronized groups make new files automatic; human-gate fallout only |
| `Reflect/ReflectApp.swift` | **T2 only** (one adaptor line) |
| `Reflect/App/AppDelegate.swift` | T2 → T22 |
| `Reflect/App/DIContainer.swift` | T11 → T13 → T14 → T18 → T20 → T21 (strict) |
| `Reflect/Presentation/Features/MainTab/MainTabView.swift` | **T15 only** |
| `Reflect/Services/Space/SpaceCloudService*.swift` | T4 → T17 → T22 |
| `Reflect/Data/Repositories/{Protocols,Implementations}/SpaceRepository*.swift` | T9 → T17 |
| `Reflect/Presentation/Features/Space/List/SpaceListView.swift` | T14 → T19 (terms gate) → T20 (destination swap) |
| `Reflect/Core/**/Constants.swift` | **T3 only** (Limits) + T22 (UserDefaults keys) — if contention, T22 defines keys in its own file |

## Human gates — UNMISSABLE (the orchestrator cannot green-light past these)

> **Two physical devices + two iCloud accounts are the #1 schedule risk (plan §11.5/§13.5).**
> Simulators cannot receive CloudKit silent pushes and cannot exercise share acceptance.
> Agents can BUILD and COMMIT every ticket below on simulator; they can NEVER fully VERIFY the
> starred items without the user's hardware.

| Gate | Ticket | What ONLY the human can do | Blocks |
|---|---|---|---|
| **H1** | T6 | Developer-portal **Push Notifications capability** check on the App ID; CloudKit Console Development record types/indexes; prepare device #2 + iCloud account #2 | T7 |
| **H2** | T7 | **Two-device spike round trip** — create/share/accept/write-back on hardware. **P0 exit criterion.** | Merging anything past checkpoint R2; all P1 UI verification |
| **H3** | T16 | Two-device **P1 flow verification** (invite, join, leave, remove, delete) through the real UI | T24 |
| **H4** | T23 | **Deploy CloudKit schema to Production** — release-blocking if forgotten; TestFlight talks to Production | T24 |
| **H5** | T24 | **TestFlight two-device E2E** incl. silent-push observation and cold-install invite UX | Ship decision; feeds T25 |

Tickets whose acceptance is split **build-green (agent) vs hardware-verified (human)**:
T2, T4, T5, T12, T13, T14, T15, T17, T20, T21, T22 — each says so in its Acceptance line. The
orchestrator must track both bits separately; "build green" on these is NOT "done done".

## Review checkpoints (bring Fable back as reviewer)

1. **R1 — after Wave 1 (T1+T2+T3+T8)**: `plutil` evidence for both Info.plist keys in the built
   product; `ReflectApp.swift` diff is exactly one adaptor line; entities are CloudKit-free and
   `Sendable`; `SpaceStore` schema contains only the three cache models. *Gap signature*: keys
   missing from the built product (silent merge failure), a `UIWindow` created in `SceneDelegate`
   (black screen), or cache models with SwiftData relationships.
2. **R2 — after T7/H2 (P0 exit)**: the spike addendum is committed with an explicit
   manual-ops-vs-`CKSyncEngine` decision; the T4 service routes every op by lane. **Nothing merges
   into P1 UI until R2 passes.** *Gap signature*: accept callback never fired (T1/T2 mis-wire), or
   share created without atomic root+share (works locally, breaks on accept).
3. **R3 — after T15 (before P2 fans out)**: three tabs; widget deep links regression-tested;
   `WidgetAction` NOT extended; celebration/onboarding intact; accept-routing queues metadata
   under presented covers. *Gap signature*: `.modelContainer` slapped on the Spaces tab, a new
   `WidgetAction` case breaking exhaustive switches, or accept-routing fighting the
   fullScreenCover.
4. **R4 — after T18 (before UI Wave 8 continues)**: `isMine`/owner guards live in use cases;
   every child save sets `record.parent`; cache upserts keyed by record name with scoped
   delete-stale. *Gap signature*: a view calling the repository directly, a guard living only in
   SwiftUI, or `parent` unset (children silently missing for participants — the classic CKShare
   bug).
5. **R5 — after T24/H5, gating T25 close-out**: triage TestFlight findings — ≤10-line fixes go to
   T25 inline; anything structural (push reliability, accept UX, consistency surprises) comes back
   to Fable for follow-up tickets, not executor redesign.

## Branch note (orchestrator)

All work on **`feature/space`**, branched from `develop` @ `ede4e71` (or a dedicated worktree,
e.g. `.../Repo's/Reflect/Reflect-space`, to keep `develop` buildable — mind the iCloud-Drive
sync gotcha for new worktrees). One commit per ticket, house commit style, **no push** — the user
pushes and opens the PR to `develop`. Human-gate fallout (Xcode rewriting pbxproj/entitlements)
gets reconciled and committed at the next review checkpoint, never silently absorbed into an
executor ticket.
