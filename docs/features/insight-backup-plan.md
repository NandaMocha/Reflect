# Plan: Insight iCloud Backup + Backup Progress/Error Surfacing

Status: **planned** (no code changed yet). Written 2026-07-28 by the planner agent. Two executor tracks implement directly from this document.

## Overview

Two objectives, one feature area (Settings → iCloud Sync):

1. **Backup Insight** — Insights are currently local-only (`cloudKitDatabase: .none` in `Shared/Insight/InsightStore.swift:30`). Extend the existing **manual** backup/restore flow so Insights ride the same "Backup to iCloud" / "Restore from iCloud" buttons, stored in the user's **private** CloudKit database.
2. **Backup progress status** — the ViewModel already tracks progress and errors, but the view never shows an error alert and hides the progress bar at the start of an operation. Surface both.

**Scope**: manual backup/restore parity only. Insight does **not** join the incremental auto-sync path (`pushUpserts`/`pushDeletes`/`SyncCoordinator`) — that is an explicit follow-up (see "Out of scope / follow-ups").

## Verified design facts (file:line citations)

| Fact | Where verified |
|---|---|
| Manual CloudKit sync (no SwiftData auto-CloudKit); records go to `container.privateCloudDatabase` — private DB is per-Apple-ID, so "private per account" is already satisfied by the existing architecture | `Reflect/Services/Cloud/CloudSyncService.swift:12-14`; comment at `:30-32` confirms hand-rolled record types, not `CD_` mirroring |
| `RecordType` enum lists only CKLearning, CKReflection, CKImageAttachment, CKVoiceRecording, CKVideoAttachment — **no Insight**; zero `Insight` references anywhere in `Reflect/Services/Cloud/` (grep confirmed) | `CloudSyncService.swift:33-41` |
| Backup flow: `backup(learnings:reflections:)` calls `deleteAllCloudData()` first, then uploads | `CloudSyncService.swift:105-176` (delete at `:124`), `deleteAllCloudData()` at `:250-265` iterates `RecordType.all` |
| Restore flow: `restore(applying:)` downloads a `CloudBackupSnapshot` then hands it to a `@Sendable @MainActor` apply closure | `CloudSyncService.swift:178-219`, snapshot assembly `fetchBackupSnapshot()` at `:225-248` |
| Cloud summary: `checkExistingData()` counts each record type + last backup date | `CloudSyncService.swift:65-103`; paging helpers `fetchRecordCount` `:273`, `fetchAllRecords` `:288`, `forEachPage` `:309` |
| Data gathering happens in the ViewModel: `backup()` fetches Learnings/Reflections from the **main** `modelContext` and calls the service | `Reflect/Presentation/Features/Settings/CloudSync/CloudSyncViewModel.swift:158-200` (fetch at `:176-180`); `restore()` `:206-234`; `loadCloudDataSummary()` `:120-126` sets `errorMessage` on failure |
| Restore writes go through `RestoreFromCloudUseCase.apply(_:to:)`, which wipes then re-inserts into the **main** context in one `save()` | `Reflect/Domain/UseCases/Sync/RestoreFromCloudUseCase.swift:58-153`, wipe at `:159-165` |
| **Insight lives in a separate App-Group store**, not the main `modelContext`: `InsightStore.container` with config name `"Insight"`, `groupContainer: .identifier("group.xyz.nandamochammad.Reflect")`, `cloudKitDatabase: .none`, tiered fallback (App Group → local → in-memory) | `Shared/Insight/InsightStore.swift:21-57` |
| `Insight` model fields: `@Attribute(.unique) id: UUID`, `text`, `typeRawValue: String` (typed accessor `type`), `followUp: String = ""`, `createdAt`, `updatedAt` | `Shared/Insight/Insight.swift:7-39` |
| `InsightType` cases: `question`, `note`; `Insight.type` getter falls back to `.note` for unrecognized raw values — so restore of a future/unknown type raw value degrades safely | `Shared/Insight/InsightType.swift:9-12`, `Insight.swift:36-39` |
| Insight CRUD: `Reflect/Data/Repositories/Implementations/InsightRepository.swift` + use cases in `Reflect/Domain/UseCases/Insight/` (Create/Update/Delete/Fetch) — none of these need changes for manual backup parity |
| Progress infra already exists: `SyncStatus` enum (`.idle/.checking/.syncing(progress:)/.completed/.failed`) at `Reflect/Domain/Entities/SyncResult.swift:83-105`; service publishes via `syncStatusPublisher` (`CloudSyncService.swift:16-24`); VM mirrors it (`CloudSyncViewModel.swift:37-44`) and exposes `isSyncing`/`isBackingUp`/`isRestoring`/`syncProgress` (`:52-72`) and `errorMessage` (`:13`) |
| **View gaps (Objective 2)**: `CloudSyncView.swift` never renders `viewModel.errorMessage` — no `.alert` for it anywhere (the only alert is the restore confirmation at `:59-68`). The progress bar at `:332-336` is gated on `progress > 0 && progress < 1`, so it is invisible at the start of a backup (service sends `.syncing(progress: 0)` at `CloudSyncService.swift:109/181`) and during `.checking`. `isBackingUp` and `isRestoring` are indistinguishable (both just test `.syncing`, `CloudSyncViewModel.swift:57-65`), so both buttons re-label during either operation | `Reflect/Presentation/Features/Settings/CloudSync/CloudSyncView.swift` |
| Manual backup already pauses the auto-sync coordinator (`beginPause`/`endPause`) so delete-then-reupload doesn't race incremental pushes; restore does the same inside the use case | `CloudSyncViewModel.swift:170-172`, `RestoreFromCloudUseCase.swift:43-45` |

## Design decisions

1. **New record type `CKInsight`** in `RecordType` (and `RecordType.all`). Adding it to `all` automatically includes Insights in `deleteAllCloudData()` — required so backup's delete-then-reupload also clears stale insight records.
2. **Pass DTOs, not `@Model` objects, across the service boundary for Insight.** Existing `backup()` takes live `Learning`/`Reflection` models (a known non-Sendable wart tolerated per CLAUDE.md). Do **not** extend that pattern to a second store: define `CloudInsightRecord` (Sendable value type, mirroring `CloudLearningRecord`) and extend the signature to `backup(learnings:reflections:insights: [CloudInsightRecord])`. The ViewModel converts `Insight` → `CloudInsightRecord` on the MainActor before calling the service.
3. **Read/write the Insight store via a dedicated `ModelContext(InsightStore.container)`**, created on the MainActor in the ViewModel (backup read) and in `RestoreFromCloudUseCase` (restore write). Never touch `Insight` through the main app `modelContext` — it isn't in that schema and would throw.
4. **Restore stays "replace, not merge"** for Insights too, matching the alert copy ("replace all your local data"). The apply step wipes `Insight` rows from the Insight context and re-inserts from the snapshot. Because the main store and the Insight store are **separate containers, the two saves cannot be one transaction** — order the saves main-store-first and treat an Insight-store save failure as a thrown restore error (see risks).
5. **Empty-snapshot guard stays keyed on learnings/reflections.** `CloudBackupSnapshot.isEmpty` will include insights in `totalItems`, but the restore guard's purpose (`CloudSyncService.swift:197-201`, don't wipe on an empty download) is preserved automatically. Also keep `checkExistingData()`'s early-bail at `CloudSyncService.swift:83-86` keyed on learnings+reflections being 0 **OR** extend to `&& insightsCount == 0` — decision: extend it, so an insights-only backup is still discoverable/restorable.
6. **`CKInsight` record shape** (deterministic `CKRecord.ID(recordName: id.uuidString)` via the existing `recordID(_:)` helper at `CloudSyncService.swift:685-687`, `localID` written as a field for the decode path, matching every other type):
   - `localID: String`, `text: String`, `typeRawValue: String`, `followUp: String`, `createdAt: Date`, `updatedAt: Date`. No assets, no relationships — the simplest record type in the schema.
7. **Objective 2 = surface, don't rebuild.** Add an error `.alert` bound to `viewModel.errorMessage`, fix the progress-bar visibility gate to show whenever `syncStatus.isInProgress` (helper already exists at `SyncResult.swift:90-97`), and disambiguate backup vs restore with a tiny `activeOperation` enum on the ViewModel so button labels are truthful.

---

## Objective 1 tasks — Backup Insight (Track A)

### Task A1 — `CloudInsightRecord` DTO + snapshot field
- **Goal**: Sendable value type carrying an Insight across the actor boundary; snapshot slot for restore.
- **Files**: `Reflect/Domain/Entities/CloudBackupSnapshot.swift`
- **Changes**:
  - Add `struct CloudInsightRecord: Sendable { let id: UUID; let text: String; let typeRawValue: String; let followUp: String; let createdAt: Date; let updatedAt: Date }`.
  - Add `var insights: [CloudInsightRecord] = []` to `CloudBackupSnapshot`; include `insights.count` in `totalItems` (`:22-24`).
- **Accept**: builds; `CloudBackupSnapshot().isEmpty` semantics unchanged for empty snapshots.

### Task A2 — service: record type, encode, decode, fetch
- **Goal**: `CloudSyncService` uploads, downloads, counts, and deletes `CKInsight` records.
- **Files**: `Reflect/Services/Cloud/CloudSyncService.swift`
- **Changes**:
  1. `RecordType`: add `static let insight = "CKInsight"`; append to `all` (`:33-41`). This alone extends `deleteAllCloudData()` (`:250`).
  2. Add `makeRecord(_ dto: CloudInsightRecord) -> CKRecord` next to the other builders (`:588+`), using `recordID(dto.id)` and writing `localID`, `text`, `typeRawValue`, `followUp`, `createdAt`, `updatedAt`.
  3. Add `decodeInsight(_ record: CKRecord) -> CloudInsightRecord?` next to the other decoders (`:356+`): require `localID`; default `text`/`followUp` to `""`, `typeRawValue` to `"note"`, dates to record dates (mirror `decodeLearning` at `:372-385`).
  4. `backup(...)`: extend signature to `backup(learnings:reflections:insights: [CloudInsightRecord])`; include `insights.count` in `totalItems` (`:120`); after the reflections loop (`:145-156`), upload insights via `database.save(Self.makeRecord(dto))` wrapped in `uploadWithRetry(maxRetries: 3)`, incrementing `itemsSynced` and publishing `.syncing(progress:)` per item, appending `.uploadFailed("Insight")` on per-item failure (mirror the reflections loop).
  5. `fetchBackupSnapshot()` (`:225-248`): fetch `RecordType.insight`, decode into `snapshot.insights`. Re-space the intermediate progress constants (e.g. 0.15/0.35/0.55/0.7/0.82, insights last before return) — exact values are cosmetic.
  6. `checkExistingData()` (`:65-103`): count insights; extend early-bail at `:83` to `learningsCount == 0 && reflectionsCount == 0 && insightsCount == 0`; pass into `CloudDataSummary`.
- **Accept**: build green; every `RecordType.all` consumer still compiles; no change to `pushUpserts`/`pushDeletes`.

### Task A3 — protocol + summary types
- **Goal**: keep protocol and summaries in sync with A2.
- **Files**: `Reflect/Services/Cloud/CloudSyncServiceProtocol.swift`, `Reflect/Domain/Entities/SyncResult.swift`
- **Changes**:
  - `CloudSyncServiceProtocol.backup` signature gains `insights: [CloudInsightRecord]` (`CloudSyncServiceProtocol.swift:10-13`).
  - `CloudDataSummary` (`SyncResult.swift:107-121`): add `let insightsCount: Int`; include in `totalItems`. Grep verified: the **only** constructor call site in the repo is `CloudSyncService.checkExistingData` (`CloudSyncService.swift:92-98`) — update it; re-grep `CloudDataSummary(` after editing to confirm nothing new appeared.
- **Accept**: build green; grep shows no `CloudDataSummary(` call missing the new argument.

### Task A4 — ViewModel: gather insights for backup; local count
- **Goal**: backup sends Insights read from the Insight store; local summary shows the count.
- **Files**: `Reflect/Presentation/Features/Settings/CloudSync/CloudSyncViewModel.swift`
- **Changes**:
  - In `backup()` (`:158-200`), after fetching learnings/reflections (`:176-180`): create `let insightContext = ModelContext(InsightStore.container)`, `fetch(FetchDescriptor<Insight>())`, map to `[CloudInsightRecord]`, pass to `cloudSyncService.backup(learnings:reflections:insights:)`. (`backup()` is `@MainActor`, so context creation/fetch is main-actor-bound — fine.)
  - `LocalDataSummary` (`:239-252`): add `let insightsCount: Int`; populate in `loadLocalDataSummary()` (`:129-146`) via `ModelContext(InsightStore.container).fetchCount(FetchDescriptor<Insight>())` with the same `(try? …) ?? 0` style.
- **Accept**: build green; backup path compiles with the new signature; no `@Query`/main-context access to `Insight`.

### Task A5 — restore writes Insights into the Insight store
- **Goal**: restore replaces local Insights from the snapshot.
- **Files**: `Reflect/Domain/UseCases/Sync/RestoreFromCloudUseCase.swift`
- **Changes**:
  - In `apply(_:to:)` (`:58-153`), after the main-store `context.save()` (`:150`): create `let insightContext = ModelContext(InsightStore.container)`; `try insightContext.delete(model: Insight.self)`; insert one `Insight(id:text:type:followUp:createdAt:updatedAt:)` per `snapshot.insights` record (use the `InsightType(rawValue:) ?? .note` fallback via the model's `type` accessor, i.e. construct with `type: InsightType(rawValue: record.typeRawValue) ?? .note`); `try insightContext.save()`; add inserted count to the return value.
  - Keep ordering: main store save first, Insight store second (see Risks R2).
- **Accept**: build green; restore of a snapshot with zero insights leaves the Insight store **wiped** (consistent replace semantics) — this is intentional and matches the alert copy; document in code comment.

### Task A6 — View: show Insight counts (Track A owns this view edit)
- **Goal**: Local Data and iCloud Data sections show Insights.
- **Files**: `Reflect/Presentation/Features/Settings/CloudSync/CloudSyncView.swift`
- **Changes**: add a `DataCountCard` (component at `:373-399`) for Insights in `localDataSection` (`:227-265`) using `viewModel?.localDataSummary?.insightsCount ?? 0` (do **not** add an `@Query` for `Insight` — wrong container) and in `cloudDataSection` (`:269-301`) using `data.insightsCount`. Icon: `lightbulb.fill` (or the app's existing Insight tab icon — check `MainTabView`); color from existing tokens (no hardcoded colors, per CLAUDE.md).
- **Accept**: build green; counts render; no new `@Query`.

### Task A7 — build verification + commit (Track A)
- Run the standard build check (see "Build verification" below), fix until green, then commit Track A as one commit (message: `Add Insight to manual iCloud backup/restore`).

---

## Objective 2 tasks — Backup progress status (Track B)

> **Precondition: Track A is fully committed first.** See Executor partition.

### Task B1 — ViewModel: operation kind + alert plumbing
- **Goal**: distinguish backup vs restore; make `errorMessage` alert-bindable.
- **Files**: `Reflect/Presentation/Features/Settings/CloudSync/CloudSyncViewModel.swift`
- **Changes**:
  - Add `enum SyncOperation { case backup, restore }` and `var activeOperation: SyncOperation?` (State section). Set `.backup` at the top of `backup()`, `.restore` at the top of `restore()`, reset to `nil` in a `defer` in each.
  - Rewrite `isBackingUp` → `activeOperation == .backup && syncStatus.isInProgress`; `isRestoring` → `activeOperation == .restore && syncStatus.isInProgress` (replacing the identical bodies at `:57-65`). Keep `isSyncing` as `syncStatus.isInProgress` (covers `.checking` too).
  - Add `var isShowingError: Bool { get { errorMessage != nil } set { if !newValue { errorMessage = nil } } }` for `.alert(isPresented:)` binding.
- **Accept**: build green; during a backup only the backup button re-labels, during a restore only the restore button.

### Task B2 — View: error alert + always-visible progress while running
- **Goal**: user sees a spinner/bar while backup/restore runs and an alert when it fails.
- **Files**: `Reflect/Presentation/Features/Settings/CloudSync/CloudSyncView.swift`
- **Changes**:
  1. **Error alert**: add `.alert("Sync Error", isPresented: Binding(get: { viewModel?.isShowingError ?? false }, set: { if !$0 { viewModel?.errorMessage = nil } }))` with an OK button and `message: Text(viewModel?.errorMessage ?? "")`. This covers backup errors, restore errors, and `loadCloudDataSummary()` failures — all already funnel into `errorMessage` (`CloudSyncViewModel.swift:124/193/197/227/231`).
  2. **Progress**: replace the gate at `:332-336` (`progress > 0 && progress < 1`) with: show whenever `viewModel?.isSyncing == true` — a determinate `ProgressView(value:)` when `syncProgress > 0`, an indeterminate `ProgressView()` with a label ("Backing up…" / "Restoring…" / "Checking iCloud…" from `activeOperation`/`syncStatus`) when progress is still 0 or status is `.checking`.
  3. **Both buttons disabled during any operation**: extend both `.disabled(...)` modifiers (`:316`, `:325-329`) with `viewModel?.isSyncing == true` so a restore can't start mid-backup and vice versa.
- **Accept**: build green; starting a backup immediately shows a progress indicator (even at progress 0); a forced failure (e.g. airplane mode) presents the alert with the error text; dismissing the alert clears `errorMessage`.

### Task B3 — build verification + commit (Track B)
- Run the build check, fix until green, commit as one commit (message: `Surface backup/restore progress and error alerts in CloudSyncView`).

---

## Executor partition

**Execution is SEQUENTIAL, not parallel: Track A (Sonnet) runs to completion and commits before Track B (Haiku) starts.** Both tracks must edit `CloudSyncViewModel.swift` and `CloudSyncView.swift`; assigning halves of a file to two concurrent agents is not safe, so we serialize instead. Order: **A1 → A2 → A3 → A4 → A5 → A6 → A7 (commit) → B1 → B2 → B3 (commit)**.

| Track | Executor | Tasks | Files touched |
|---|---|---|---|
| **A — Backup Insight** | Sonnet | A1–A7 | `Reflect/Domain/Entities/CloudBackupSnapshot.swift`, `Reflect/Services/Cloud/CloudSyncService.swift`, `Reflect/Services/Cloud/CloudSyncServiceProtocol.swift`, `Reflect/Domain/Entities/SyncResult.swift`, `Reflect/Presentation/Features/Settings/CloudSync/CloudSyncViewModel.swift`, `Reflect/Presentation/Features/Settings/CloudSync/CloudSyncView.swift`, `Reflect/Domain/UseCases/Sync/RestoreFromCloudUseCase.swift` (+ any other `CloudDataSummary(` call sites found by grep) |
| **B — Progress status** | Haiku | B1–B3 | `Reflect/Presentation/Features/Settings/CloudSync/CloudSyncViewModel.swift`, `Reflect/Presentation/Features/Settings/CloudSync/CloudSyncView.swift` — **only after Track A's commit exists** |

Shared/foundational changes (`RecordType.insight`, `CloudInsightRecord`, snapshot field, `backup` signature, `CloudDataSummary.insightsCount`) are **all owned by Track A**. Track B introduces no new types beyond the `SyncOperation` enum and touches nothing in `Services/` or `Domain/`.

## Build verification (both tracks, before their commit)

Per CLAUDE.md standing rule:

```bash
xcodebuild -project Reflect.xcodeproj -scheme Reflect \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -configuration Debug build 2>&1 | grep "error:"
```

Loop until grep is empty, then confirm `** BUILD SUCCEEDED **` in the unfiltered tail. Swift 6 non-Sendable warnings are pre-existing and not blockers. (Repo is in iCloud Drive — a build error in an untracked, unrelated file is likely stray iCloud WIP, per project memory.)

## CloudKit Console (manual step — NOT code, do after Track A ships)

CloudKit creates the `CKInsight` record type on first write (Development environment). Then, in the CloudKit Console for the app's default container:

1. Development → Schema → Record Types → `CKInsight` → add a **Queryable index on `recordName`**. Without it, the default-zone `CKQuery(TRUEPREDICATE)` used by `forEachPage` fails with *"Field 'recordName' is not marked queryable"* — this exact error is already live for the existing record types, so fix it for **all six** types while there.
2. Deploy schema changes to **Production**.
3. Optional (auto-sync reconcile parity, existing note at `CloudSyncService.swift:777-781`): mark `reflectionID` queryable on the attachment types — unrelated to Insight but same console visit.

## Risks

- **R1 — App-Group store bridging**: `InsightStore.container` degrades to a local or in-memory store if the App Group entitlement fails (`InsightStore.swift:32-56`). Backing up from an in-memory fallback backs up nothing, and restoring into it doesn't persist. Acceptable for v1 (same degradation the whole Insight feature already has); do not add extra handling.
- **R2 — Two stores, two transactions**: restore saves the main store, then the Insight store. If the Insight save throws after the main save succeeded, the user has restored reflections but stale/wiped insights, and the thrown error marks the whole restore failed. Mitigation: Insight save is tiny (no assets) so failure is unlikely; the error alert (Task B2) tells the user to retry; retrying is safe because restore is idempotent (wipe + re-insert). Document in a code comment at the A5 site.
- **R3 — Delete-then-reupload racing**: `backup()` wipes the cloud before uploading (`CloudSyncService.swift:124`). A backup that dies mid-upload leaves a partial cloud backup — pre-existing behavior, now also affecting insights. The existing coordinator pause (`CloudSyncViewModel.swift:170-172`) already prevents auto-sync racing the manual backup; Insight has no auto-sync path, so no new race is introduced.
- **R4 — `InsightType` migration**: current cases are `question`/`note` (`InsightType.swift:9-12`). Backup stores the raw string, and both the decode default and the model's `type` accessor fall back to `.note` (`Insight.swift:37`), so restoring a backup containing a raw value from a future app version degrades to `.note` instead of crashing. `typeRawValue` is preserved verbatim through backup/restore, so no data is lost even when the accessor falls back.
- **R5 — `CloudDataSummary` init churn**: adding `insightsCount` breaks every constructor call. Grep verified only one call site exists today (`CloudSyncService.swift:92`); re-grep before declaring A3 done in case one lands in the meantime.

## Out of scope / follow-ups

- **Live incremental auto-sync for Insight** (`pushUpserts`/`pushDeletes`/`SyncCoordinator` enqueue from `InsightRepository`): explicitly deferred. Manual backup parity ships first; auto-sync for Insight is a separate feature with its own reconcile/first-enable design.
- Quick Actions extension writes Insights into the same App-Group store; those are picked up by the next manual backup automatically — no extension changes needed.
