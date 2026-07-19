# Swift-latest codebase review (SwiftUI / SwiftData / Concurrency)

_Reviewed on `feature/space-p2` by four independent Fable passes using the swift-pro skills
(swiftui-pro ×2, swiftdata-pro, swift-concurrency-pro), targeting the latest Swift. 209 Swift
files. Read-only review — no code changed._

**Headline:** the codebase is already largely modern (Observation everywhere, `NavigationStack`,
`Tab(value:)`, two-parameter `.onChange`). The real risks cluster in two places: **(a) SwiftData
`@Model` objects read off the main actor** (genuine data races) and **(b) uncoordinated refresh
triggers in the Space feature** (visible data flicker/loss). Several high-value bugs are in the
newly-built Space code.

Findings are deduped across the four passes. `T#` = tier. Each has a source tag: `[cc]` concurrency,
`[sd]` swiftdata, `[ui-s]` swiftui-space, `[ui-c]` swiftui-core.

---

## Tier 1 — Correctness bugs (fix before ship)

1. **`@Model` objects read off the main actor — data race / crash.** `[cc]`
   - `Reflect/Presentation/Features/Reflection/List/ReflectionListViewModel+Grouping.swift:11` —
     `groupReflectionsByDate()` sends live `Reflection` models into `Task.detached` and reads
     `createdAt` on a background thread while main can delete/mutate them. Pointless offload (~ms
     work). Fix: drop the detached task, group synchronously (needs #14).
   - `Reflect/Services/Cloud/CloudSyncService.swift:227,278` — backup task-group reads
     `learning.title` / `reflection.contentData` / `image.imageData` on concurrent executors.
     Fix: snapshot each model into a `Sendable` value struct on the main actor before the task group.

2. **Reflection search is case-sensitive — "Titanic" is unfindable.** `[sd]`
   `ReflectionRepository.swift:47` lowercases the query but compares with case-sensitive `contains`.
   Fix: `localizedStandardContains` on title + plain-text content, drop `lowercased()`.

3. **Uncoordinated Space refreshes clobber optimistic updates.** `[ui-s C3]` `[cc 6]`
   Each Space screen fires `refresh()` from up to four triggers (`.task`, `.onReceive`,
   `scenePhase`, sheet-dismiss) as detached `Task {}`s; `isRefreshing` is set but never gates
   reentry. A fetch started before a post/delete can finish after it → a just-posted response
   vanishes or a deleted row resurrects until next sync. `SpaceListViewModel.refresh:62`,
   `SpaceDetailViewModel`, `SpaceThreadViewModel:78`. Fix: `guard !isRefreshing else { return }`,
   or hold/cancel the in-flight refresh `Task`.

4. **SpeechRecognitionService — races + cancellation busy-spin.** `[cc 3]`
   `Reflect/Services/Speech/SpeechRecognitionService.swift` — audio-tap callback reads/writes
   `recognitionRequest`/`audioFile` (:180) while `cleanup()` nils them (:314); `try? Task.sleep`
   inside `waitForFinalTranscription` (:269) defeats cancellation → ~2s of 100% CPU on every stop;
   duration timer (:232) can double-`stopRecording` and lose the recording at max duration.
   Fix: make it an actor (or `@MainActor` with an `AsyncStream` from the tap), store+cancel the
   timer task, let the sleep throw.

5. **`ensureDatabaseSubscription` burns ~6s on every launch after the first.** `[cc 5]`
   `SpaceCloudService.swift:446` catches `.serverRejectedRequest` ("already exists") *outside*
   `withRetry`, so each of the two subscription saves fails → sleeps 1s → fails → sleeps 2s → …
   before being swallowed. Fix: move the tolerate-already-exists inside, or don't retry it.
   _(This is T22 code.)_

6. **`.constant(...)` alert bindings can loop / desync.** `[ui-s C2]` `[ui-c C1]`
   `isPresented: .constant(viewModel.errorMessage != nil)` drops SwiftUI's dismissal write; a
   background `refresh()` failing while the alert is up can re-present it. Sites: `SpaceListView:83`,
   `SpaceDetailView:47`, `SpaceThreadView:59`, `MainTabView:92`, `InsightListView:58`,
   `ReflectionListView:95`. Fix: one `errorAlert(_ message: Binding<String?>)` modifier with a real
   two-way binding (`SpaceListView.dialogBinding` is the right shape). _(Matches an existing
   codebase pattern, but the reviewers flag it as a genuine desync risk.)_

7. **Edit-response sheet dismisses even when the save failed.** `[ui-s C4]`
   `SpaceThreadView.swift` `SpaceResponseEditSheet` Save calls `onSave` (which swallows the error
   into `errorMessage`) then unconditionally `dismiss()`es — the edited text is lost behind an
   alert. Fix: make `onSave` return `Bool`, dismiss only on success (mirror the compose sheet).

8. **Deleting/leaving a space orphans its cached children forever.** `[sd 2]`
   `SpaceRepository.removeCached(id:)` / `reconcileCache` prune only the `CachedSpace` row; the
   flattened schema has no cascade, so `CachedSpaceReflection`/`CachedSpaceResponse` rows for that
   space are never deleted (storage growth, stale rows resurface if an id recurs). Fix: on space
   delete/leave, also delete the space's cached reflections and their responses.

9. **ViewModel created inside a sheet closure — the "orphaned VM" bug, again.** `[ui-c C2]`
   `LearningListView.swift:96` builds `BadgeGridViewModel(modelContext:)` inside `.sheet` content,
   re-created on every re-render. This repo already root-caused this exact class of bug
   (`docs/reviews/achievement-counter-root-cause.md`). Fix: `@State` VM created once, or let the
   child own it.

10. **`syncChanges` never sees zone deletions.** `[cc 10]`
    `SpaceCloudService.fetchDatabaseChanges:470` sets only `recordZoneWithIDChangedBlock`; a space
    deleted/left on another device increments nothing → `syncChanges()` returns `false` → the
    silent-push path reports `.noData`. Fix: also set `recordZoneWithIDWasDeletedBlock` /
    `…WasPurgedBlock`. _(T22 code.)_

11. **`withRetry` retries non-idempotent creates and permanent failures.** `[cc 5]`
    `createReflection`/`createResponse` use `database.save`; a lost-ack retry fails with
    `serverRecordChanged` and shows an error for a write that actually committed. It also retries
    auth/quota/`badRequest` and ignores `retryAfterSeconds`. Fix: retry only transient CKError
    codes, rethrow `CancellationError`, treat post-retry `serverRecordChanged` on a create as success.

## Tier 2 — Isolation / strict-concurrency adoption (needed for "latest Swift")

12. **`SpaceCloudService`: `lazy var` DB race + should be an `actor`.** `[cc 4,8]`
    `lazy var privateDB/sharedDB` (:25) can race on concurrent first-touch (see #3). Converting the
    service to an `actor` fixes it, retires `userRecordNameLock`, and lets the CK return values use
    `sending` result types — the *correct* resolution of the tolerated non-Sendable warnings
    (the warnings mostly point at #1/#4, not the CK hand-offs).

13. **8 of 11 core-app ViewModels lack class-level `@MainActor`.** `[ui-c B7]` `[cc 7]`
    `SettingsViewModel`, `CloudSyncViewModel`, `LearningFormViewModel`, `LearningListViewModel`,
    `OnboardingViewModel`, `ReflectionDetailViewModel`, `ReflectionListViewModel`,
    `ReflectionEditorViewModel` annotate individual methods instead — observable state is mutable
    off-main. Violates the project's own CLAUDE.md convention. `ReflectionListViewModel` is the worst
    (mixed isolation + the detached task in #1). Fix: `@MainActor` on the class, delete per-method
    annotations.

14. **`DIContainer` should be `@MainActor`.** `[cc 11]` `static let shared` of a non-Sendable class
    with mutable `modelContext` is a strict-mode error; half the factories already are. All call
    sites (incl. AppDelegate `Task`s) are main-actor.

15. **Missing migration plan.** `[sd 3]` No `VersionedSchema`/`SchemaMigrationPlan` for any of the
    three stores; the next non-lightweight change throws at `ModelContainer` init → `fatalError`
    (main) or silent in-memory fallback (Space/Insight = perceived data loss). Define versioned
    schemas now while all changes are still lightweight.

16. **ObservableObject / NavigationView holdouts.** `[ui-c B1,B2]`
    `VoiceAudioView.swift:449,475` (`AudioRecorderWrapper`/`SpeechRecognizerWrapper` +
    `@Published`/`@StateObject`) are the only legacy-Observation types. `NavigationView` remains in
    `LearningListView:97` and `BadgeDetailView:20`.

17. **Explicit `@MainActor` on services + repositories** rather than relying on the target-level
    default-actor build setting. `[sd 4]` `[cc 13]` (AudioRecorderService, and the repos that hold
    `mainContext`). Also: AppDelegate/SceneDelegate are already `@MainActor` protocols — annotate the
    classes and drop the `assumeIsolated` no-ops. `[cc 12]`

## Tier 3 — Performance & modernization (mechanical, opportunistic)

- **`#Index` on hot query fields** (`Reflection.createdAt`/`isFavorite`, `CachedSpaceReflection.spaceID`,
  `CachedSpaceResponse.reflectionID`). `[sd 6]`
- **Reconcile does N+1 fetches** (`upsert` fetches per row inside a loop that then re-fetches all).
  Fetch once into `[id: row]`, upsert in memory, one save. `[sd 5,8]` Add `fetchLimit = 1` to point
  lookups. `[sd 8]`
- **`foregroundColor` → `foregroundStyle`** (169 uses, 44 files) and **`cornerRadius` →
  `clipShape(.rect(cornerRadius:))`** (6) — one mechanical sweep each. `[ui-c B4,B5]`
- **Accessibility**: zero `accessibilityLabel` in Presentation; icon-only buttons (Space `+`,
  compose, send; core FAB/IconButton) and `onTapGesture` cards (BadgeGridView:243) are invisible to
  VoiceOver. `[ui-s B1]` `[ui-c C5]`
- **`DispatchQueue.main.asyncAfter` stragglers** → `Task.sleep`/animation-completion APIs
  (`ReflectApp:131`, `LearningListView:176`, `ReflectionListView:154`, `FloatingActionMenu:119,152`,
  `ShakeEffect:36`). `[cc 14]`
- **`.onAppear { Task {} }` → `.task`** for loads (`ReflectionListView:112`, `LearningListView:125`,
  `CelebrationView:60`). `[ui-c B9]`
- **`sheet(isPresented:)+if let` → `sheet(item:)`** (`SpaceFormView:83` share sheet). `[ui-s B2]`
- **Dead code**: `Components/Universal/ConfirmationAlert.swift` (`makeAlert`/`StandardAlerts`,
  0 refs, deprecated `Alert`); commented-out block in `SettingsView.swift:85-115`; removed-streak
  computed props in `Reflection.swift:92`. `[ui-c B13]` `[sd 13]`
- **Stringly-typed `Notification.Name("ReflectionDidSave")`** inline (×4) → a named constant, or
  drop it for `@Query`. `[ui-c B12]`
- **Deprecated toolbar placements** `.navigationBarLeading/Trailing` → `.topBarLeading/Trailing`
  (3 sites). `[ui-c B3]`
- **One-type-per-file / extract subview structs** in the Space views (Thread has 4 types) and the
  ~700-line `VoiceAudioView`. `[ui-s B7]`
- **`ReflectionEditorView`**: ~25 non-private `@State` business-state vars shared across 8 extension
  files despite an existing `@Observable` VM — migrate into the VM. `[ui-c B8]`

---

## What's already right (keep it)

Observation-based `@Observable @MainActor` Space VMs owned via `@State` and passed to children as
plain `let`; three-store isolation is verified sound (no `default.store` collision; `.unique`
attributes are legal because every store is `cloudKitDatabase: .none`); relationships declared
one-side with explicit delete rules + inverse; predicates capture locals and use only stored
scalars; explicit `save()` after each mutation; continuation hygiene (every wrapped CK operation
resumes exactly once); `.refreshable` `CancellationError` correctly swallowed; modern `Tab(value:)`,
`NavigationStack`, two-parameter `.onChange` throughout.
