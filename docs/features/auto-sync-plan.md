# Auto-Sync to iCloud — Implementation Plan (Path B: Transactional Outbox)

**Status:** In progress (Tasks 1–5 implemented; Tasks 6–7 in progress)
**Author:** Claude (design), reviewed by Fable + Sonnet agents
**Target:** iOS 17+, Swift 6, SwiftData + CloudKit (private DB)
**Base branch:** `feature/first-open-instructions` (verified against this, not `origin/main`)
**Feature branch:** `feature/auto-sync-impl` (active development worktree)

> **v2 changelog:** Fixed the load-bearing wrong assumption (CloudKit records are keyed by a
> `localID` attribute, NOT by recordName); corrected conflict semantics to last-push-wins;
> moved the Sendable-DTO fix into the push API; made the outbox write transactional; handle
> child-record deletes via `reflectionID`; expanded repo hook coverage; corrected file paths.

---

## Implementation Status

**Tasks 1–5** (PendingSyncOp model, incremental push API, SyncCoordinator, repository enqueue hooks, lifecycle flush + BGProcessingTask) have been implemented on `feature/auto-sync-impl` and verified:
- Build: `xcodebuild ... | grep error:` passes (no compile errors).
- Code review: each task reviewed by a code-review skill pass for concurrency correctness, architecture alignment, and error handling.

**Tasks 6–7** (restore/seed guard + first-enable re-key, settings toggle + status surfacing) are in progress.

**Verification:** CloudKit Dashboard schema prerequisite (see [auto-sync-verification.md](auto-sync-verification.md#prerequisites)) and manual acceptance checks are pending. Each check is documented in [auto-sync-verification.md](auto-sync-verification.md).

---

---

## 1. Goal

Move from **manual, full-replace backup** to **automatic, incremental sync**. Every create /
update / delete of a `Learning` or `Reflection` is persisted to SwiftData first, then
propagated to the user's **private CloudKit database** in the background — without the user
tapping "Back Up Now" in Settings.

**Out of scope:**
- SwiftData native mirroring (`cloudKitDatabase: .automatic`) — forbids `@Attribute(.unique)`,
  forces optional properties, needs a store migration, collides with Spaces `CKShare`.
- Real-time two-way pull. This plan is **push-on-change**; pull stays the existing `restore()`
  path (which is real and functional on this branch, `CloudSyncService.swift:178-206`). A
  follow-up can add pull-on-launch.
- Conflict-merge UI (see §5 for the honest policy: last-push-wins per key).

---

## 2. Current-state facts (verified in code on `feature/first-open-instructions`)

| Fact | Location |
|---|---|
| Store is local-only, no auto-mirror | `Reflect/ReflectApp.swift:52-53` — `groupContainer: .none`, `cloudKitDatabase: .none` |
| **Records are keyed by a `localID` attribute, NOT recordName** | `CloudSyncService.swift:537,551,592,615,637` create `CKRecord(recordType:)` with **no** `CKRecord.ID`; decode matches on `localID` (`:366`), children on `reflectionID`/`learningID` (`:391,405,420,437`) |
| Backup is **full delete-then-reupload** | `CloudSyncService.swift:124` — `deleteAllCloudData()` runs first |
| Backup triggered **only manually** | `CloudSyncViewModel.swift:175` (Settings) |
| Record types incl. video | `CloudSyncService.swift:33-40` — `CKLearning/CKReflection/CKImageAttachment/CKVoiceRecording/CKVideoAttachment` (video **is** uploaded, `:582-637`) |
| `restore()` is real (not a stub) | `CloudSyncService.swift:178-206` — downloads snapshot, calls `apply` |
| Writes funnel through repositories | `Data/Repositories/Implementations/{Reflection,Learning}Repository.swift` — each calls `context.save()` |
| iCloud availability + backoff exist | `CloudSyncService.checkCloudAvailability()`; throttle handling `~:503-521` |
| `AppDelegate` exists (Spaces share handling) | `Reflect/App/AppDelegate.swift` — usable for `BGTaskScheduler` registration |
| `RestoreFromCloudUseCase` exists | `Domain/UseCases/Sync/RestoreFromCloudUseCase.swift` |

**Key correction from v1:** CloudKit identity is the `localID` field. Any incremental upsert
must therefore either (a) **re-key** records to deterministic `CKRecord.ID(recordName: uuid)`,
or (b) look up the existing record by `localID` before modifying. This plan chooses (a) — see
Task 2 — because it makes upserts O(1) and idempotent, at the cost of a one-time re-key of
already-backed-up data (handled by the first-enable full backup, Task 6).

---

## 3. Architecture overview

```
Repository mutate + enqueue(op)  ──►  ONE context.save()   (entity change + PendingSyncOp atomic)
                                              │
                                              ▼
                                   SyncCoordinator.scheduleDrain()
                                              │  debounce ~3s + coalesce by entityID
                                              ▼
                                   drain: fetch pending ops → map to Sendable DTOs
                              ┌───────────────┴────────────────┐
                              ▼                                 ▼
                CloudSyncService.pushUpserts([DTO])   CloudSyncService.pushDeletes([DTO])
                (deterministic CKRecord.ID(recordName))  (delete parent by recordName;
                              │                            children by reflectionID query)
                              └──────────► success: delete ops · failure: attempt++/backoff
```

**Trigger strategy (validated by both reviewers):** event-driven enqueue on every write +
debounced drain + flush on background/foreground + `BGProcessingTask` backstop + `CKAccountChanged`
/ `NWPathMonitor` retriggers. NOT list-refresh, NOT purely periodic.

---

## 4. Tasks

Each task: **scope / out-of-scope / files / acceptance / risk**. Ordered; each builds green
(`xcodebuild ... | grep error:` empty) before the next. Acceptance is verified via `xcodebuild`
+ **manual CloudKit Dashboard inspection** (no test target exists yet).

---

### Task 1 — `PendingSyncOp` outbox model + schema registration
**Scope:**
- New `@Model final class PendingSyncOp` (`Data/Models/PendingSyncOp.swift`):
  `id: UUID (.unique)`, `entityType: String` (learning|reflection), `entityID: UUID`
  (== the record's `localID`), `op: String` (upsert|delete), `enqueuedAt: Date`,
  `attemptCount: Int = 0`, `lastError: String? = nil`, and for delete ops of reflections,
  `childRecordHint` is **not** needed (children are deleted server-side by `reflectionID`).
- Register `PendingSyncOp.self` in the `Schema([...])` array at `Reflect/ReflectApp.swift:32`.
- **No** SwiftData relationship to `Reflection`/`Learning` (a delete op must outlive its row).
- Do **not** add it to the Insight/App-Group store (`Shared/Insight/InsightStore.swift`).
**Out of scope:** enum-typed columns; any coordinator logic.
**Files:** `Data/Models/PendingSyncOp.swift` (new), `Reflect/ReflectApp.swift`.
**Acceptance:** builds; insert + fetch a `PendingSyncOp` in the main store; **upgrade path**
verified on a store that already holds data (purely additive → lightweight migration).
**Risk:** LOW-MEDIUM. Additive migration is safe; still verify upgrade, not just fresh install.

---

### Task 2 — Incremental push API with deterministic record IDs + Sendable DTOs
**Scope:**
- Introduce **Sendable snapshot DTOs** (`LearningSnapshot`, `ReflectionSnapshot` incl. child
  image/voice/video sub-DTOs carrying their bytes/asset URLs). These cross the actor boundary,
  **not** `@Model` objects.
- Extend `CloudSyncServiceProtocol`:
  - `func pushUpserts(_ learnings: [LearningSnapshot], _ reflections: [ReflectionSnapshot]) async throws`
  - `func pushDeletes(_ deletions: [SyncDeletion]) async throws`
    (`SyncDeletion { entityType, entityID: UUID }`).
- Implement by extracting the CKRecord mapping from `backup()` into helpers that build records
  with **`CKRecord.ID(recordName: entityID.uuidString)`** (deterministic) while still writing
  the `localID`/`reflectionID`/`learningID` fields for backward-compatible restore.
  - `pushUpserts`: `CKModifyRecordsOperation` with `savePolicy = .changedKeys`, batched (reuse
    `batchSize` + backoff), **no** leading `deleteAllCloudData()`. For a reflection upsert, also
    reconcile its children: delete server-side child records for that `reflectionID` that are no
    longer present, then upsert current children (prevents orphaned attachments on removal).
  - `pushDeletes`: for a reflection, delete `CKReflection/<uuid>` **and** query+delete child
    records where `reflectionID == uuid`; for a learning, delete `CKLearning/<uuid>` (reflections
    that referenced it are re-upserted with cleared `learningID` — see Task 4).
- **Re-key migration:** because existing backups have random recordNames, the first auto-sync
  enable performs a one-time full `backup()` that now writes deterministic IDs (Task 6). After
  that, all records are addressable by UUID. Document this; do not attempt in-place rename.
**Out of scope:** coordinator, scheduling, repo hooks, UI.
**Files:** `Services/Cloud/CloudSyncServiceProtocol.swift`, `Services/Cloud/CloudSyncService.swift`,
new DTO file (`Services/Cloud/SyncSnapshots.swift`).
**Acceptance (manual):** call `pushUpserts` twice for one reflection → CloudKit Dashboard shows
exactly one `CKReflection` record (no dupes) under recordName = UUID; remove an attachment and
re-push → orphaned child record is gone; `pushDeletes` on a missing record does not throw.
**Risk:** HIGH — this is the crux. Deterministic IDs + child reconciliation + Sendable DTOs must
all land together. The existing `backup()` `withTaskGroup` (`:227-248`) has a latent non-Sendable
capture; the new DTO path must not reproduce it.

---

### Task 3 — `SyncCoordinator` (debounce + drain + gating)
**Scope:**
- `@MainActor @Observable final class SyncCoordinator` (`Services/Cloud/SyncCoordinator.swift`).
  Deps: `CloudSyncServiceProtocol`, `ModelContext`.
  - `func enqueueContext()` returns the outbox insertion so repos write it in **their own**
    `context.save()` (transactional — see Task 4), then call `scheduleDrain()`.
  - `scheduleDrain()`: cancellable `Task` + `Task.sleep(~3s)` debounce, coalescing bursts.
  - `drain()`: guard `checkCloudAvailability() == .available`; fetch `PendingSyncOp`s; resolve
    `entityID` → live `Learning`/`Reflection`, map to **DTOs on the main actor**, then call the
    async push off-actor; on success delete drained ops; on failure bump `attemptCount`,
    set `lastError`, capped exponential backoff, reschedule. Cap attempts (~5) → park as `failed`.
  - Expose `syncState` + `pendingCount`; a `paused` flag (Task 6).
- Wire in `DIContainer.makeSyncCoordinator()`; own one instance from app launch.
**Out of scope:** lifecycle/BG (Task 5); repo enqueue calls (Task 4); UI (Task 7).
**Files:** `Services/Cloud/SyncCoordinator.swift` (new), `App/DIContainer.swift`,
`Reflect/ReflectApp.swift` (hold instance).
**Acceptance (manual):** insert 3 ops + `drain()` → uploaded, outbox empty; iCloud off → ops
remain, `syncState == .offline`.
**Risk:** MEDIUM. DTO mapping must happen on the main actor before the network hop. Debounce
cancellation race-free.

---

### Task 4 — Repository enqueue hooks (transactional)
**Scope:**
- In `ReflectionRepository` create/update/delete/**toggleFavorite** and `LearningRepository`
  create/update/delete/**reorder**: insert the `PendingSyncOp` into the **same** `ModelContext`
  and let the **existing single `context.save()`** commit entity + op atomically (no post-save
  enqueue — avoids losing the op on a crash between save and enqueue).
- Delete path builds the op with the id captured **before** deletion.
- Attachment add/remove → enqueue an **upsert of the parent reflection**.
- **Learning delete** nullifies its reflections (`Learning.swift:15`, `.nullify`) → also enqueue
  **upserts for each affected reflection** so their cloud `learningID` is cleared, not left stale.
- Inject `SyncCoordinator` into these two repositories via `DIContainer`.
**Out of scope:** Badge/MonthlyAchievement/Insight/Space repos (not in the backup record set).
**Files:** `Data/Repositories/Implementations/ReflectionRepository.swift`, `LearningRepository.swift`,
`App/DIContainer.swift`.
**Acceptance (manual):** create → one op → drains to Dashboard; delete → cloud record gone;
toggle favorite → op enqueued; delete a learning with N reflections → learning record removed and
those reflections re-pushed with empty `learningID`.
**Risk:** MEDIUM. Must not enqueue during restore/import (Task 6 `paused`). Confirm there is no
separate repo `move` method on this branch (reassignment goes through a use case) — hook wherever
`context.save()` for the reassignment lands.

---

### Task 5 — Lifecycle flush + `BGProcessingTask` backstop
**Scope:**
- Flush on `scenePhase → .background` and on foreground/launch (`coordinator.drain()`), wired in
  `Reflect/ReflectApp.swift` / `App/AppDelegate.swift`.
- Register one `BGProcessingTask` (`xyz.nandamochammad.Reflect.sync-drain`) in `ReflectApp.init`
  (or `AppDelegate`); handler drains, requires network, reschedules.
- Info.plist: add `UIBackgroundModes` → `processing` **and** the identifier under
  `BGTaskSchedulerPermittedIdentifiers` (both required).
- `beginBackgroundTask` around an in-flight drain when backgrounding so an active upload survives.
**Out of scope:** CKSubscription silent-push sync (future; AppDelegate has Spaces push plumbing
but this plan doesn't extend it).
**Files:** `Reflect/ReflectApp.swift`, `App/AppDelegate.swift`, `Info.plist`.
**Acceptance (manual):** backgrounding with pending ops drains them; an op created offline is
picked up on next foreground or BG run.
**Risk:** MEDIUM. BG tasks are best-effort (not the only path). Info.plist identifier must match
exactly or registration throws at launch.

---

### Task 6 — Restore/seed guard + first-enable re-key backup
**Scope:**
- Bracket `RestoreFromCloudUseCase` / onboarding restore / bulk import with
  `coordinator.paused = true` so seeding the local store does not enqueue a re-upload storm;
  after completion `paused = false` **without** draining the imported rows.
- **First-enable path:** when a user with existing local data turns Auto-sync ON, run a one-time
  full `backup()` (which now writes deterministic recordNames — Task 2) to **re-key** any prior
  random-named cloud data, then switch to incremental. Do this inside the `paused` bracket.
- Also bracket the manual "Back Up Now" (`backup()` = delete-all-then-upload) with `paused` +
  await any in-flight drain, so it can't race incremental pushes.
**Out of scope:** changing restore's internal logic beyond the pause bracket.
**Files:** `Domain/UseCases/Sync/RestoreFromCloudUseCase.swift`, `OnboardingViewModel.swift`,
`Services/Cloud/SyncCoordinator.swift`, `CloudSyncViewModel.swift`.
**Acceptance (manual):** restoring N items produces **zero** new ops; first-enable on a device
with prior backups leaves exactly one record per entity (no random-named orphans).
**Risk:** MEDIUM-HIGH. Missing the guard double-syncs every restore; missing the re-key leaves
duplicate cloud records forever.

---

### Task 7 — Settings toggle + status surfacing
**Scope:**
- "Auto-sync" `Toggle` in CloudSync settings, persisted (`@AppStorage`). When **off**, skip
  enqueue entirely (respect intent); when re-enabled, run the Task 6 first-enable reconcile.
- Surface `syncState`/`pendingCount` ("All changes synced" / "Syncing… / N pending / Last synced
  <time>") in `CloudSyncView`.
- Keep "Back Up Now" as an explicit "force full re-upload".
**Out of scope:** settings redesign; per-item sync indicators.
**Files:** `Presentation/Features/Settings/CloudSync/CloudSyncView.swift`, `CloudSyncViewModel.swift`.
**Acceptance:** toggling off stops new ops; on reconciles; status reflects reality.
**Risk:** LOW.

---

## 5. Cross-cutting concerns

- **Conflict policy (corrected):** `savePolicy = .changedKeys` on freshly built records =
  **last-push-wins per key** — nothing compares `updatedAt`. Acceptable for a single-user
  journal. If multi-device concurrent edits become a concern, add a server-record fetch +
  `updatedAt` compare before push (future work); do not claim LWW-by-updatedAt today.
- **Coexistence with Spaces:** Spaces → **shared** DB via `CKShare`; this outbox → **private**
  DB via `CK*` types. No overlap.
- **Idempotency:** deletes tolerate not-found; upserts keyed by deterministic recordName → replay-safe.
- **Failure isolation:** cap `attemptCount` (~5) → park op as `failed`, surface in Settings for
  manual retry; never hot-loop.
- **Attachments (`.externalStorage`):** DTOs stream bytes/asset URLs from external storage as
  `CKAsset`, matching `backup()`'s asset handling; child reconciliation prevents orphans.
- **Offline retriggers:** subscribe to `CKAccountChanged` (`NotificationCenter`) and reachability
  (`NWPathMonitor`) so ops queued offline drain on reconnect without waiting for a lifecycle event.
- **Testing:** no test target; verification = `xcodebuild` green + manual CloudKit Dashboard.
  Design `SyncCoordinator` with injected sleep so a future Swift Testing suite can drive it.

---

## 6. Sequencing & PR strategy

One draft PR per task (or grouped: 1-2, 3-4, 5-6, 7). Feature behind the Settings toggle
(default OFF) until all land, so partial merges are safe. Task 2 is the critical path — land its
deterministic-ID + DTO design before anything depends on it.

## 7. Resolved / open questions

- **[RESOLVED] Record identity:** it's `localID`, not recordName → adopt deterministic recordNames
  + one-time re-key backup on first enable (Task 2 + 6).
- **[RESOLVED] Conflict semantics:** last-push-wins per key (§5), documented honestly.
- **Open — bandwidth:** reflection-aggregate re-upload re-pushes all attachment `CKAsset`s on any
  edit (even a favorite toggle). Accept for v1, or diff attachments to skip unchanged assets? Diff
  adds complexity; recommend accepting for v1 with a note, revisit if users have large videos.
- **Open — pull-on-launch:** add now (closes "edited on device B" gap, restore path already exists)
  or defer? Recommend defer to a follow-up; this plan is push-only.
- **Open — first-enable UX:** the one-time re-key backup can be large; show progress and require
  Wi-Fi? Recommend gating the first full backup on the existing availability check + a progress UI.
