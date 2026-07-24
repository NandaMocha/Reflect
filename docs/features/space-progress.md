# Space Feature — Session Continuation / Handoff

> **Read this first to resume the Space build.** Self-contained: a fresh session should not
> need the prior chat. Companion docs: [space-plan.md](space-plan.md) (design + locked
> decisions), [space-tasks.md](space-tasks.md) (the 25-ticket breakdown — the source of truth
> for what each ticket does, its files, acceptance, executor, and the wave/lock tables).

_Last updated: 2026-07-20 (feature merged to `develop`; post-P2 UX + launch screen + icon fix)._

## TL;DR status (2026-07-20)

**The entire Space feature is CODE-COMPLETE and MERGED into local `develop`** (merge commit
`80b1e59`, `--no-ff`). P0 (CloudKit foundation) + P1 (UI, R3 review) + P2 (child records/UI/push,
R4 review) all landed. `develop` builds green on the iPhone 17 (iOS 26.2) simulator and is
**installed on _Nanda iPhone 16_**. **Nothing is pushed** — `develop` is ~90 commits ahead of
`origin/develop`, all local.

**Feature branches/worktrees still exist** (untouched, as history/backup): `feature/space`
(P0 @`16bfd31`), `feature/space-p1` (@`8a86611`), `feature/space-p2` (@`8d63ece`). New work is now
done directly on **`develop`** (in the `.../Reflect/Reflect` worktree) — the stacked-worktree phase
is over.

### Done since P2 (all on `develop`)
- **Response editing** + split the thread into a **"Your feedback"** compose page and a separate
  **"All feedback"** page (toolbar button) — write your own before seeing others.
- **Peer-feedback reframe (UI copy only):** a space's seed post is now a **feedback request**
  ("Ask for Feedback"), replies are **feedback**. Personal side stays **Reflection** →
  Reflect(privately) / Feedback(from others) duality. **CloudKit record types + Swift types are
  UNCHANGED** (`SpaceReflection`/`Response`), so the schema is untouched. See
  [space-appreview-notes.md](space-appreview-notes.md).
- **swift-latest codebase review** (4 Fable passes, swift-pro skills) → [swift-latest-review.md](../reviews/swift-latest-review.md);
  Tier 1/2/3 fixes applied. Key discovery: target sets `SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor`,
  which made several "off-main races" already safe (so SpaceCloudService→actor was NOT needed).
  Deferred: schema migration plan, deep SpeechRecognitionService rewrite, N+1 reconcile (documented).
- **UX:** brand-green `AccentColor` (tab bar + accents now green, not system blue); Settings gear on
  ALL tabs (shared `SettingsToolbarButton`); tab bar hides on push **except** the reflection list
  (it's the restore-to default landing); date-grouped feedback list (`SpaceReflectionDateGroup`);
  search field hidden on empty lists (`ConditionalSearchable`); destructive confirms use `.alert`.
- **Launch screen:** centered app icon (100pt, light/dark) on an adaptive `LaunchBackground`
  (`UILaunchScreen` in Info.plist; `UILaunchScreen_Generation=NO`).
- **App-icon fix (App Store 90717):** primary 1024 icon had a transparent margin → **flattened to
  opaque** (filled with its light-sage edge color). Dark/tinted keep alpha per HIG. Re-archive/upload
  should now pass.

### Remaining before ship (ALL hardware/human — none are code)
- **H2** two-device spike accept round-trip (needs **Device B** = 2nd iCloud account; Device A
  passed avail/create/share/probe-write). Use Settings → 🧪 Space Debug on the installed build.
- **H3** two-device P1 UI verification (incl. the R4-F1 `isMine` authorship check on the shared lane,
  + cold-launch invite).
- **H4** CloudKit Console: **deploy schema Dev→Production** (record types `Space`/`SpaceReflection`/
  `Response` + subscriptions) — release footgun; TestFlight talks to Production.
- **H5** TestFlight two-device E2E incl. silent push.
- **R5** review (triage H5 findings) + **T25** final regression/decoupling audit.
- Optional: **push `develop`** to origin when ready (agents never push).

## P1 status (built on `feature/space-p1`)

Worktree: `.../Reflect/Reflect-space-p1`. All tickets build green on the iPhone 17 simulator,
grep-gate clean, committed (no push).

| Ticket | Commit | What |
|---|---|---|
| T9 | `6442b58` | `SpaceRepository` (+protocol) — cloud-through cache, cloud-leads, both-lane reconcile |
| T10 | `8dbd3c3` | 5 use cases under `Domain/UseCases/Space/` (create/fetch/delete/leave/accept) w/ owner guards |
| T11 | `ac56d5c` | DIContainer `// MARK: - Space` factories (service, repo, 5 use cases) |
| T13 | `07c3e0a` | Create-space form (`SpaceFormViewModel`/`View`) → presents `CloudSharingView` on success |
| T14 | `bc46fd9` | Spaces list (`SpaceListViewModel`/`SpaceRowView`/`SpaceListView`) — owner Delete vs joined Leave (§11.3 copy), iCloud-unavailable state |
| — | `7011c4e` | `SpaceListView` `openSpace` deep-link binding (list nav contract, enables T15) |
| T15 | `991a72f` | Spaces tab in `MainTabView` + accept-invite routing (queues metadata behind onboarding/celebration covers) |

**Detail navigation is a placeholder `Text`** until P2's T20 swaps in `SpaceDetailView`.

### R3 review — DONE (2026-07-19)

Independent review (Fable) of `16bfd31..` (the P1 slice). **All four R3 gap signatures passed clean**
(three tabs; no `.modelContainer` on the Spaces tab; `WidgetAction` not extended; onboarding/
celebration intact with the invite queued behind covers). Findings remediated:

- `6fca38f` — 6 inline fixes: accept-failure now alerts (was silent); a second invite arriving
  mid-accept is drained (was queued forever); `load()` force-reconciles (no stale spaces across
  launches); reconcile grace window prevents accept→mirror-lag eviction; deep-link repaints from
  cache; form Cancel disabled while saving.
- `8c26798` — **cold-launch invites (finding #1)**: added `SpaceInviteInbox` + a window-free
  `scene(_:willConnectTo:)` so an invite tapped while the app is closed is no longer dropped.
  Simulator-verified: launches with content (no black screen), three tabs render.

**Tracked follow-up (not yet done):** R3 finding #7 — `SpaceDebugView` (DEBUG-only) also observes
`.spaceShareInviteReceived` and accepts directly, so with that screen open in a DEBUG build an invite
is double-accepted. Left as-is on purpose (it's the H2 spike harness — don't change mid-test); gate
or remove it once H2/H3 are done and T15 routing is the sole path. Zero production impact (`#if DEBUG`).

**Open P1 gate:** **H3** (two-device: create→invite→join→leave→remove→delete through the real UI,
incl. cold-launch invite). Must pass before P2 (T17+). H3 still depends on H2's accept round-trip
(Device B) passing first.

## P2 status (built on `feature/space-p2`)

Worktree: `.../Reflect/Reflect-space-p2` (branched from `feature/space-p1` @ `8a86611`). Built ahead
of H2/H3 at the user's request. All build green on the iPhone 17 (iOS 26.2) simulator, grep-clean,
committed, **not pushed**.

| Ticket | Commit | What |
|---|---|---|
| T17 | `ed30953` | Service + repository child CRUD (reflections/responses): parent refs carry the share; children fetched via zone-changes; author/`isMine` resolution; cache-through with scoped grace-windowed reconcile + response cascade |
| T18 | `d8d3cee` | Child use cases (create/fetch reflections & responses, delete-own w/ `isMine` guard) + DI factories; new SpaceError cases |
| T19 | `e469e5b` | UGC compliance: `SpaceTermsSheet` (one-time, gated by `spaceHasAcceptedTerms`), `ReportContentButton` (mailto), `space-appreview-notes.md` |
| R4 fixes | `bfe4184` | Remediations (see below) |

### R4 review — DONE

Independent review of `8a86611..` (T17–T19). **All 3 gap signatures clean** (parent refs set; guards
in use cases; scoped delete-stale). 7 findings; fixed in `bfe4184`:
- **F1 (security):** `isMine` made **lane-aware + fail-closed** in the shared DB — `__defaultOwner__`
  there is the share owner, not the current participant, so it no longer counts as mine (prevented a
  participant seeing a delete affordance on the owner's content). **Still wants two-device
  confirmation** of the shared-lane creator record-name semantics (H3/T24).
- **F2:** deleting a reflection now **cascades** to its response records (parent action `.none`
  doesn't cascade server-side — responses were orphaning).
- F3 user-record-name cache race → locked. F4 prompt length validated. F5 author lookup reuses the
  fetched records (no 2nd zone scan). F6 report-button fallback alert. F7 comment fixes.

### P2 UI + sync (T20–T22) — BUILD-COMPLETE

| Ticket | Commit | What |
|---|---|---|
| T20 | `0d804aa` | Space detail (`SpaceDetailViewModel`/`View`) — reflections list, compose, delete-own, report; replaces T14's placeholder destination; `SpaceListView` → type-erased `NavigationPath` |
| T21 | `fea0aa1` | Response thread (`SpaceThreadViewModel`/`View`) — comment-style bubbles, always-visible composer, delete-own + report per response |
| T22 | `922655a` | DB subscriptions + silent-push sync: `ensureSubscriptions` (idempotent), `syncChanges` (per-DB tokens in UserDefaults, reset-on-expiry), AppDelegate push handler, and the 3 Space views refresh on `spaceRemoteChangeReceived` + scenePhase `.active` |

**Full feature is code-complete** (P0 + P1 + P2). Smoke-verified on the iPhone 17 (iOS 26.2) simulator:
launches cleanly with three tabs (no crash from launch-time `ensureSubscriptions` when signed out).

Notes/simplifications recorded during T22:
- `syncChanges` advances **database-level** change tokens (persisted, simulator-checkable) and drives
  a full re-fetch via the VMs' refresh — it does NOT do per-zone incremental upsert, because the
  repository uses full zone fetches. Correct for the "fetch makes it correct" model; a future
  optimization if needed.
- No save-conflict handling: the model is append-only (create + delete, no field edits), so
  `serverRecordChanged` conflicts don't arise (noted in `SpaceCloudService`).

### Remaining before ship (all hardware/human)

- **R5** — review after H5 (triage TestFlight findings).
- **H2** (accept round-trip, Device B), **H3** (two-device P1 UI), **H4** (CloudKit Console: deploy
  schema Dev→**Production** — release footgun), **H5** (TestFlight two-device E2E incl. silent push).
- **T25** — final regression + decoupling audit + polish (after H5).
- **R4 F1 still wants two-device confirmation** of the shared-lane `creatorUserRecordID` semantics
  (the `isMine` authorship model) — fail-closed now, proven by H3/T24.

## (historical) P0 next-step — H2 spike

**Do not build the P1 UI until H2 passes** — H2 exists to de-risk the CloudKit foundation before
investing in UI (per plan §12 / task doc checkpoint R2). _(P1 was subsequently built ahead of the
H2 accept round-trip in the isolated `feature/space-p1` branch at the user's explicit request; the
de-risk rationale still applies to **merging** and to **P2**.)_

## Where everything lives

- **Branch / worktree:** all Space work is on **`feature/space`**, in the dedicated worktree
  `/Users/nandamochammad/Library/Mobile Documents/com~apple~CloudDocs/Documents/Repo's/Reflect/Reflect-space`.
  Branched from `develop` (currently `b63b246`). **Do all Space work in that worktree.** Other
  worktrees: `.../Reflect` (`develop`), `.../Reflect-insight` (`feature/insight`) — **do not touch**.
- **feature/space @ `5b5d825`**, 7 commits ahead of `develop`, working tree clean, **not pushed**.
- Repo lives in **iCloud Drive** — a build error in an untracked/unrelated file is likely stray
  iCloud WIP; check `git status` before chasing it.

## What's done (P0 — 7 tickets, all build-green + committed)

| Ticket | Commit | What |
|---|---|---|
| T1 | `8a3c2a1` | `Reflect/Info.plist`: `CKSharingSupported` + `UIBackgroundModes[remote-notification]` (verified in built product) |
| T2 | `a5e797e` | `Reflect/App/AppDelegate.swift` (AppDelegate+SceneDelegate: share-accept + silent-push entry points, notif names `spaceShareInviteReceived`/`spaceRemoteChangeReceived`) + one-line `@UIApplicationDelegateAdaptor` in `ReflectApp.swift` |
| T3 | `88059a1` | `Reflect/Domain/Entities/Space/` value types (`Space`, `SpaceReflection`, `SpaceResponse`, `SpaceZoneRef`+`SpaceLane`, `SpaceError`) + `Constants.Limits` (space{Name/ReflectionTitle/Response}MaxLength) |
| T8 | `316353b` | `Reflect/Data/Space/` isolated `SpaceStore` (InsightStore pattern, store name `"Space"`, `cloudKitDatabase:.none`) + `CachedSpace`/`CachedSpaceReflection`/`CachedSpaceResponse` @Model classes |
| T4 | `e5a3cd8` | `Reflect/Services/Space/` — `SpaceCloudService` core: `CKContainer(identifier:)`, custom zone per space, **atomic root+CKShare** in one `CKModifyRecordsOperation`, dual-DB (private=owner / shared=joined) lane routing, `acceptShare` via `CKAcceptSharesOperation` + `hierarchicalRootRecordID`, delete/leave with lane guards |
| T5 | `f77535f` | `Reflect/Presentation/Features/Space/Debug/SpaceDebugView.swift` — **`#if DEBUG` spike harness** (Settings → 🧪 Space Debug), drives `SpaceCloudService` directly |
| T12 | `5b5d825` | `Reflect/Presentation/Features/Space/Share/CloudSharingView.swift` — `UICloudSharingController` wrapper (existing-share initializer, `.allowReadWrite/.allowPrivate`) |

Checkpoint **R1 passed** (Info.plist keys in built product; `ReflectApp.swift` diff = 1 adaptor
line; entities CloudKit-free; `SpaceStore` isolated from main schema; no `UIWindow` in SceneDelegate).

## Human gates status

- **H1 — Push capability + entitlements: ✅ DONE/VERIFIED.** `aps-environment=development` is in the
  committed entitlements AND in the signed device build; the App ID already has Push enabled (a
  `-allowProvisioningUpdates` device build signs cleanly). No Xcode capability change needed.
  - Still yours for H1: **a second device with a second iCloud account** (Device B). CloudKit
    Console record types auto-create on first write during the spike.
- **The current feature/space build (with the spike harness) is INSTALLED on _Nanda iPhone 16_**
  (devicectl id `6920DFDC-D656-5ABD-9AA5-A9BB73DBF989`) — that's **Device A**.
- **H2 — two-device spike: ⏳ PENDING (next action).**

## ▶ NEXT ACTION: run H2 (two-device spike). P0 exit criterion.

On **both** devices: Settings → **🧪 Space Debug (spike)**:
1. Device A: Check availability → Create test space → Share invite → send link via Messages.
2. Device B: tap link → app opens & accepts → List joined spaces shows it → Write probe reflection.
3. Device A: Dump zone records → sees B's record.

If all pass → **H2 green**; commit a one-line outcome note to `space-plan.md` §12 and proceed to P1.
If broken: likely culprits are the atomic root+share (T4) or the accept callback wiring (T1/T2) —
see task doc T7 watch-outs.

## After H2 passes — resume P1, then P2 (execution recipe below)

Execute the remaining tickets **in this order** (from [space-tasks.md](space-tasks.md); respect the
shared-file lock table there):

- **P1:** T9 (SpaceRepository) → T10 (use cases) → T11 (DIContainer factories) → T13 (create-space
  form) → T14 (spaces list) → **T15 (Spaces tab + accept routing — only ticket touching
  `MainTabView.swift`)** → **R3 review** → H3 (two-device P1 verification).
- **P2:** T17 (service/repo child CRUD) ∥ T19 (UGC compliance) → T18 (child use cases) → **R4
  review** → T20 (space detail) → T21 (response thread) → T22 (subscriptions/push) → H4 (deploy
  CloudKit schema to **Production**) → H5 (TestFlight E2E) → **R5** → T25 (final audit).

**Remaining human gates:** H3 (two-device P1 UI), H4 (Console: deploy schema Dev→Production — release
footgun), H5 (TestFlight two-device E2E incl. silent push). Tickets T13/T14/T15/T17/T20/T21/T22 are
"build-green (agent) vs hardware-verified (human)" — track both bits.

**Remaining review checkpoints:** R2 (after H2), R3 (after T15, before P2), R4 (after T18), R5
(after H5). Bring Fable back as reviewer at each (the task doc lists each gap signature).

### Orchestration recipe (how this session ran the tickets)

- One agent per ticket, working **only** in the `Reflect-space` worktree. Sonnet for
  CloudKit/sync/SwiftUI/DI-wiring/delegate tickets; Haiku for mechanical mirrors. Give the agent
  its ticket's full text from `space-tasks.md`.
- Run tickets **serially** (not truly parallel) even though files are disjoint: concurrent
  `xcodebuild` on one worktree corrupts builds. The wave table is for a team/CI; here, follow
  dependency + lock order one at a time.
- Every ticket: build green on the simulator, run its grep gates, **commit on `feature/space`**
  (house style, `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>` trailer), **no push**.
- Enforce the **`DIContainer.swift` lock chain** (T11→T13→T14→T18→T20→T21) and the
  **`MainTabView.swift` = T15 only** / **service+repo file locks** (T4→T17→T22, T9→T17).

### Commands / IDs

```bash
# cd into the worktree for ALL Space work:
cd "/Users/nandamochammad/Library/Mobile Documents/com~apple~CloudDocs/Documents/Repo's/Reflect/Reflect-space"

# Simulator build (per-ticket gate):
xcodebuild -project Reflect.xcodeproj -scheme Reflect \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' -configuration Debug build 2>&1 | grep "error:"

# Device build + install (Nanda iPhone 16) — uses an out-of-tree DerivedData to avoid sim/device clashes:
DD=/private/tmp/.../scratchpad/dd-space   # or any path; -allowProvisioningUpdates handles signing
xcodebuild -project Reflect.xcodeproj -scheme Reflect -destination 'platform=iOS,name=Nanda iPhone 16' \
  -configuration Debug -allowProvisioningUpdates -derivedDataPath "$DD" build
xcrun devicectl device install app --device 6920DFDC-D656-5ABD-9AA5-A9BB73DBF989 "$DD/Build/Products/Debug-iphoneos/Reflect.app"
xcrun devicectl device process launch --device 6920DFDC-D656-5ABD-9AA5-A9BB73DBF989 xyz.nandamochammad.Reflect
```

- CloudKit container: `iCloud.xyz.nandamochammad.Reflect`. Bundle: `xyz.nandamochammad.Reflect`. Team: `9NAU7R3577`.

## Hard isolation constraints (every ticket) — from space-tasks.md

- **Never modify:** the main `Schema` in `ReflectApp.swift`, `Reflect/Data/Models/*`,
  `Shared/Insight/*`, `Reflect/Services/Cloud/CloudSyncService*`, existing repos/use cases,
  or `Reflect/Reflect.entitlements`.
- Space uses its **own** container (`CKContainer(identifier:)`, custom zones, record types
  `Space`/`SpaceReflection`/`Response`) and its **own** isolated `SpaceStore` — zero overlap with
  the personal journal or its private-DB backup.
- **Lesson banked (memory `insight-app-group-store`):** SwiftData's default `groupContainer:
  .automatic` will silently relocate a store into an App Group and collide with another store on
  `default.store`. `SpaceStore` uses `groupContainer: .none` + a distinct store name `"Space"` —
  keep it that way; never add Space models to another container's schema.
- Grep gate before each commit: new Space files must not couple to `Learning`/the personal
  `Reflection` model (the word "Reflection" appears only inside `SpaceReflection`).

## Merge/PR

When the feature lands: rebase `feature/space` onto the latest `develop`, run T25's regression +
decoupling audit, then the user pushes and opens the PR (repo rule: **agents never push**).
