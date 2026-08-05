# App Clip — Task Breakdown

> Planner output for [app-clip-plan.md](app-clip-plan.md) (incl. its "Plan Review — 2026-08-05
> (second pass)" section, whose decisions are binding here: **auto-post ingestion**, guest
> attribution via `Answer.guestId`/`guestName`, deterministic `submissionId` idempotency,
> single-pbxproj-ticket rule, `ClipDIContainer` extension pattern). Phase 0 is complete and has no
> tickets. Format follows [space-tasks.md](space-tasks.md), which executor agents ran successfully.
>
> **Execution model:** one git worktree per ticket, branched from `develop`, merged back after
> review. **Max 3 tickets concurrently per wave.** Two tickets in the same wave must never touch
> the same file — see the lock table. All paths relative to the repo root.

## Ground truth (verified 2026-08-05)

1. **CloudKit Production already has** `Space`, `SpaceReflection` (`questionsJSON`, `imageAsset`),
   `MemberProfile`, `Answer` (incl. `imageAsset`), and `PendingClipFeedback` (+2 indexes, +3 role
   grants). Legacy `Response` type and `SpaceReflection.promptText` are permanently stuck in both
   environments — dead, ignore, never reference.
2. **Still to create in CloudKit Console** (Dev first, then a new Production deploy — AC-H3):
   `MirroredRequest`, `MirroredAnswer`, `TokenIndex` public types; new fields
   `SpaceReflection.requestToken`, `Answer.guestId`, `Answer.guestName`. Server-to-server keys
   cannot create schema — Console-by-hand only.
3. **Clip App ID does not exist yet** (`xyz.nandamochammad.Reflect.Clip`) — AC-H1. Simulator
   builds don't need it; device/TestFlight work does.
4. **Hosting/AASA/signing key/write mechanism are verified working** — see plan "Hosting" and
   "Write-path spike" sections. Web root is `/home/sesirkel/nandamochammad.xyz/nandamochammad`
   (NOT `public_html`); key at `/home/sesirkel/nandamochammad.xyz/cloudkit-key.pem`.
5. **pbxproj is `objectVersion = 77` with `PBXFileSystemSynchronizedRootGroup`** — new files under
   `Reflect/` auto-join the app target. Adding the Clip target and cross-target membership
   requires real pbxproj surgery: **AC-001 is the only ticket allowed to touch it.**
6. **Working tree caution:** `develop` currently has uncommitted `project.pbxproj` +
   `SpaceThreadView.swift` changes and untracked `scripts/ExportOptions.plist`,
   `scripts/publish_testflight.sh`. The human must commit/reconcile these **before wave 1 merges**,
   or AC-001 (pbxproj) and AC-013 (Thread files) will merge-conflict.
7. Existing screens the Clip mirrors (reference only — **never** add them to the Clip target):
   `Reflect/Presentation/Features/Space/Thread/SpaceThreadView.swift`,
   `Thread/SpaceAllResponsesView.swift`, `Thread/AnswerBubble.swift`.

## Hard constraints (every ticket, every executor)

- **Clip purity grep gate** before every commit on any ticket that adds/changes Clip-target
  sources: `grep -rn "SwiftData\|DIContainer\b\|SpaceStore\|Cached" ReflectClip/ Reflect/ClipShared/`
  → zero hits (`ClipDIContainer` doesn't match `DIContainer\b`… verify with word-boundary care; the
  intent: no SwiftData, no full-app DI, no cache models, no `SpaceCloudService` in the Clip).
- **Never modify** in any ticket: the main `Schema` in `ReflectApp.swift`, `Reflect/Data/Models/`,
  `Shared/Insight/*`, `Reflect/Services/Cloud/CloudSyncService*`, `Reflect/Reflect.entitlements`
  beyond what AC-001 explicitly scopes.
- **Build gate** (no test target exists): per repo CLAUDE.md,
  `xcodebuild -project Reflect.xcodeproj -scheme Reflect -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build 2>&1 | grep "error:"`
  empty + `** BUILD SUCCEEDED **`; tickets touching the Clip additionally build the `ReflectClip`
  scheme the same way.
- Secrets: the CloudKit Key ID and `.pem` never enter the repo. PHP files in `scripts/server/`
  read key path + Key ID from a server-side `config.php` that is **gitignored and documented**,
  with a committed `config.example.php`.

---

## Tickets

Legend — Executor: **agent** = buildable/reviewable by an AI coding agent in a worktree.
**human** = portal / Console / server upload / hardware / App Store Connect / UI judgment.
IDs are grouped: 00x scaffolding, 01x full-app data, 02x Clip data, 03x Clip UI, 04x invocation,
05x submission collateral, H-x human gates.

---

### AC-001 — `ReflectClip` target scaffolding + the one pbxproj edit · agent · **HIGH RISK**
- **Scope**: The **only** ticket ever allowed to edit `Reflect.xcodeproj/project.pbxproj`:
  - New App Clip target `ReflectClip` (bundle id `xyz.nandamochammad.Reflect.Clip`, iOS 17+,
    Swift 6), embedded in the `Reflect` app target's "Embed App Clips" phase, using a new
    synchronized root group `ReflectClip/`.
  - `ReflectClip/ReflectClip.entitlements`: parent application identifiers
    (`$(AppIdentifierPrefix)xyz.nandamochammad.Reflect`), `com.apple.developer.associated-domains`
    = `appclips:nandamochammad.xyz`, CloudKit container `iCloud.xyz.nandamochammad.Reflect`,
    App Group `group.xyz.nandamochammad.Reflect` (verify the exact group id against
    `Reflect/Reflect.entitlements` and reuse it verbatim).
  - `ReflectClip/Info.plist` with `NSAppClip` keys; minimal asset catalog (accent color + Clip
    icon placeholder).
  - `ReflectClip/App/ReflectClipApp.swift`: `@main` App with
    `.onContinueUserActivity(NSUserActivityTypeBrowsingWeb)` parsing `requestToken` from
    `https://nandamochammad.xyz/f/<token>` URLs into an `@Observable ClipSession` stub; logs the
    token. Shared scheme `ReflectClip` with `_XCAppClipURL` =
    `https://nandamochammad.xyz/f/TESTTOKEN` for simulator invocation.
  - **`Reflect/ClipShared/` mechanism**: create the folder with a `README.md` and move-in nothing
    yet; configure membership-exception sets so files in `Reflect/ClipShared/` AND the existing
    entity files `Reflect/Domain/Entities/Space/{SpaceReflection,SpaceAnswer,SpaceQuestion,SpaceError}.swift`
    plus the Color/Constants token files (locate via `grep -rn "primaryDefault" Reflect/Core`)
    compile into **both** targets. Verify none of these import SwiftData/CloudKit-private APIs.
  - **Out of scope**: any real Clip UI, repositories, DIContainer content beyond an empty
    `ClipDIContainer` shell file (`ReflectClip/App/ClipDIContainer.swift`, factory-less).
- **Depends on**: none (simulator builds sign ad hoc; AC-H1 only gates device work)
- **Acceptance**: BOTH schemes build green (`Reflect` byte-identical behavior, `ReflectClip`
  launches in simulator from `_XCAppClipURL` and logs `TESTTOKEN`); Clip purity grep gate clean;
  App Thinning/baseline size note recorded in the PR description; committed.
- **Watch-outs**: objectVersion-77 target creation as a text edit is the riskiest change in this
  breakdown — validate with `plutil -lint` on the pbxproj plus a full clean build of both schemes.
  If two implement-review rounds fail, **escalate to the human to create the target via Xcode GUI**
  and let the agent reconcile the generated diff. Do not let Xcode "helpfully" add
  `Reflect/`-rooted files to the Clip target wholesale — membership exceptions must stay minimal
  and listed in `ClipShared/README.md`.

### AC-015 — PHP write endpoint (production version of the proven spike) · agent
- **Scope**: New files `scripts/server/clip-feedback.php`, `scripts/server/config.example.php`,
  `scripts/server/README.md` (deploy instructions for AC-H2: paths per Ground truth #4).
  Reuses `cloudkit_request()` signing from `scripts/appclip-cloudkit-write-test.php` (ECDSA/SHA-256
  headers, `records/modify` endpoint — see plan "Write-path spike"). Endpoint behavior:
  - `POST` JSON: `{requestToken, guestId, guestName, answers: [{questionId, submissionId, body}]}`.
  - Validate: token exists in `TokenIndex` (public-DB query; 404/410 if absent → revoked link),
    each `questionId` ∈ the request's `questionsJSON` (fetch `MirroredRequest` by token), body
    lengths ≤ the same caps as `Constants.Limits` (hardcode the numbers, comment the source),
    `guestName` non-empty ≤ 50, ≤ 5 answers per call.
  - Write one `PendingClipFeedback` per answer with deterministic
    `recordName = "pcf-" . $submissionId` and **update-or-create semantics** → retry-idempotent.
  - Rate limit: per-IP and per-token counters (flat-file or APCu, shared hosting friendly);
    HTTP 429 on breach. Structured JSON error responses; never echo the Key ID or key path.
- **Depends on**: none (contract is fixed here; AC-021 consumes it)
- **Acceptance**: `php -l` clean on all files; a `scripts/server/clip-feedback-test.md` section in
  README with curl examples for: happy path, unknown token, bad questionId, oversize body, retry
  (same submissionId twice → one record). Config values only via `config.php`. Committed.
  **Server-verified in AC-H2**, not here.
- **Watch-outs**: The public-DB *query* from PHP also needs the signed-request scheme (`records/query`
  subpath); `TokenIndex.recordName` should equal the token (`"tok-" . $token`) so lookup is a
  cheap `records/lookup`, not a query — document this shape; AC-010 must mint it identically.

### AC-016 — `/f/<token>` web landing page (fallback + Smart App Banner) · agent
- **Scope**: New files `scripts/server/f/index.php` + `scripts/server/f/.htaccess`
  (rewrite `/f/<token>` → `index.php?t=<token>`, LiteSpeed-compatible). The page: Smart App Banner
  meta (`apple-itunes-app`, `app-clip-bundle-id=xyz.nandamochammad.Reflect.Clip`), Open Graph
  tags, and a static explainer ("Open this link on an iPhone to leave feedback in Reflect") — no
  CloudKit calls, no token validation (the Clip/app do that), token never rendered into HTML
  beyond the meta URL. Add deploy notes to `scripts/server/README.md` (**shared file — this
  ticket appends a clearly-fenced section; AC-015 owns the file's creation, so AC-016 runs in the
  same wave only because README creation order is enforced: AC-015 creates, AC-016 appends — to
  keep the wave parallel-safe, AC-016 instead writes its notes to `scripts/server/f/README.md`**).
- **Depends on**: none
- **Acceptance**: `php -l` clean; rewrite rule documented; no secrets; committed. Live behavior
  verified in AC-H2.
- **Watch-outs**: Apple's AASA already registers `/f/*` for both app and Clip — do not add
  redirects on this path (Apple's fetcher and clip invocation both dislike them).

### AC-H1 — HUMAN GATE: portal + Console (Dev) setup · human
- **Scope**: (runs in parallel with wave 1)
  1. Developer portal: create App ID `xyz.nandamochammad.Reflect.Clip` with App Clip + Associated
     Domains + CloudKit + App Group capabilities; provisioning profile; confirm the AASA's appclips
     entry now resolves.
  2. CloudKit Console (**Development**): create public types with Queryable `recordName` indexes:
     - `MirroredRequest`: String `requestToken` (Queryable), `title`, `note`, `questionsJSON`;
       optional Asset `thumbnail`.
     - `MirroredAnswer`: String `requestToken` (Queryable), `questionId`, `answerIndex` (Int64),
       `authorDisplayName`, `text`, String `guestId` (optional), `sourceAnswerRecordName`.
     - `TokenIndex`: String `shareURL`, `reflectionID`, `zoneOwnerName`; recordName = `tok-<token>`.
     - Add fields to `SpaceReflection`: String `requestToken`; to `Answer`: String `guestId`,
       `guestName` (both optional).
     - Public-DB security roles: `_world` read on `MirroredRequest`/`MirroredAnswer`/`TokenIndex`;
       **no** world read on `PendingClipFeedback` (server key + owner only) — mirror the role
       grants already done for `PendingClipFeedback`.
  3. Housekeeping from the handoff: delete `appclip-cloudkit-write-test.php` and
     `.well-known/test.txt` from the server; delete stray `.php` files from the Desktop.
  4. Commit/reconcile the dirty working tree (Ground truth #6).
- **Depends on**: none · **Blocks**: runtime verification of AC-010/011/012/020, all device work.
- **Acceptance**: human replies "H1 done" with a Console screenshot of the new types.

### AC-002 — `ClipSession`, guest identity store, Clip root routing skeleton · agent
- **Scope**: In `ReflectClip/`:
  - `App/ClipSession.swift` — `@Observable @MainActor final class`: parsed `requestToken`,
    `guestIdentity: GuestIdentity?`, phase enum (`.loading/.needsName/.compose/.allFeedback/.invalidLink`).
  - `Data/GuestIdentityStore.swift` — `guestId` UUID minted once, stored in **keychain**
    (access group shared with the full app so install-migration works); display name stored
    alongside; App Group `UserDefaults` fallback mirror; protocol + live impl.
  - `App/ClipRootView.swift` — switches on session phase; placeholder screens for now.
  - `App/ClipDIContainer.swift` — fill the shell: `makeGuestIdentityStore()`, `session` wiring.
    **Convention (binding for all later Clip tickets): feature factories are added via
    `extension ClipDIContainer` inside the feature's own file — never by editing this file again.**
  - Flesh out `ReflectClipApp.swift` token parsing (error → `.invalidLink`).
- **Depends on**: AC-001
- **Acceptance**: `ReflectClip` scheme builds green; launching with `_XCAppClipURL` reaches
  `.needsName` placeholder on first run and skips it on second run (identity persisted);
  purity grep gate clean; committed.
- **Watch-outs**: Keychain access groups need the team-id prefix; simulator keychain ≠ device —
  keep the App Group mirror so simulator testing works.

### AC-010 — `requestToken` + guest-attribution schema plumbing (full app) · agent
- **Scope**: (owns the Services/Entities/Cache lock this wave)
  - `Reflect/ClipShared/ClipMirrorSchema.swift` (new, both targets): record-type + field-key
    constants for `MirroredRequest`, `MirroredAnswer`, `TokenIndex`, `PendingClipFeedback`
    (exact strings per AC-H1's list), token format (`tok-`/`pcf-` recordName conventions,
    128-bit token generation helper), and the endpoint request/response DTOs (Codable) shared
    with AC-021.
  - `Reflect/Services/Space/SpaceRecord.swift`: `requestToken` field key on SpaceReflection;
    `guestId`/`guestName` on Answer; mapper support (read+write, optional-safe).
  - `Reflect/Domain/Entities/Space/SpaceReflection.swift`: `requestToken: String?`;
    `SpaceAnswer.swift`: `guestId: String?`, `guestName: String?`, computed `isGuest`.
  - `Reflect/Data/Space/` cached models: matching optional fields + converter updates.
  - `Reflect/Services/Space/SpaceCloudService(.Protocol).swift`:
    `ensureRequestToken(for:in:) async throws -> String` — mints token if absent, saves it on the
    `SpaceReflection` record, and creates the `TokenIndex` public record (`tok-<token>`,
    shareURL from `fetchShare(for:)`, reflectionID, zoneOwnerName). Owner-only guard.
  - **Out of scope**: mirror publishing (AC-011), ingestion (AC-012), any UI (AC-013/014).
- **Depends on**: AC-001 (ClipShared folder exists)
- **Acceptance**: both schemes build green; mapper round-trips optional fields (nil-safe);
  `ensureRequestToken` idempotent (second call returns the stored token, no duplicate
  `TokenIndex`); no behavior change for non-tokenized reflections; committed.
- **Watch-outs**: `TokenIndex` recordName must be exactly `"tok-" + token` (AC-015 does
  `records/lookup` by that name). Token: 16 random bytes, base64url — no UUID (guessability).

### AC-011 — `SpaceMirrorService`: publish + revoke the public mirror · agent
- **Scope**: New `Reflect/Services/Space/SpaceMirrorService.swift` (+ protocol in the same file
  or `SpaceMirrorServiceProtocol.swift`), `SpaceMirrorError` enum, no silent `try?`:
  - After each successful sync/local write of an **owned** Space (hook: one call added at the end
    of the existing sync path in `SpaceCloudService.swift` — this ticket holds that file's lock),
    upsert `MirroredRequest` (title, note, `questionsJSON`, thumbnail from `imageAsset` if cheap)
    and `MirroredAnswer` rows (one per Answer, `answerIndex` order, `authorDisplayName` resolved
    the same way the thread does, `guestId` passthrough, `sourceAnswerRecordName` = Answer
    recordName for diffing) for every reflection with a `requestToken`.
  - Diff-based: fetch existing mirror records for the token, modify only changed, delete orphans.
  - `revokeMirror(for token:)`: delete `TokenIndex` + all mirror records for the token — called
    on request deletion, space deletion, and share revocation (wire into the existing delete
    paths in `SpaceCloudService`).
  - `Reflect/App/DIContainer.swift`: `makeSpaceMirrorService()` factory (starts the DIContainer
    lock chain AC-011 → AC-012 → AC-014).
- **Depends on**: AC-010
- **Acceptance**: build green; mirror publish is fire-and-forget off the sync path's critical
  section (an owner sync must not fail because mirror publish failed — log + retry next sync);
  revoke wired into all three deletion paths; purity gate n/a (full-app only); committed.
  Runtime behavior verified after AC-H1 (types exist in Dev) — reviewer checks code-level only.
- **Watch-outs**: Public-DB writes from the app run as the signed-in user; ensure the security
  role for record creation by authenticated users is set (AC-H1 grants). Never mirror a Space the
  user doesn't own (`isOwner` guard at the top). Batch `CKModifyRecordsOperation` ≤ 400 records.

### AC-013 — Guest attribution rendering + owner moderation (full app UI) · agent
- **Scope**: Presentation-only (AC-010 already did entities/mappers):
  - `SpaceAuthor` label logic (locate via `grep -rn "SpaceAuthor" Reflect/Presentation`): when
    `answer.isGuest`, byline = `guestName` + "· guest" marker; `isMine` styling never applies.
  - `Thread/AnswerBubble.swift`: delete affordance ALSO renders when the answer `isGuest` and the
    current user is the space **owner** (pass `isSpaceOwner` in from the thread views) —
    Decision 1's moderation affordance. Report button unchanged.
  - `Thread/SpaceThreadView.swift` + `Thread/SpaceAllResponsesView.swift`: plumb `isSpaceOwner`,
    exclude guest answers from "your answers" on the compose page.
  - VM (`SpaceThreadViewModel`): `deleteGuestAnswer` path reuses the existing own-delete use case
    if record-ownership already permits (owner created the record) — verify guard logic allows
    owner-deletes-guest and NOTHING else.
- **Depends on**: AC-010
- **Acceptance**: build green; a seeded guest answer (SwiftUI preview or debug data) renders
  guest byline, no Edit, Delete only for owner; non-owner members see report-only; committed.
- **Watch-outs**: Ground truth #6 — `SpaceThreadView.swift` has uncommitted local changes on the
  human's checkout; merge after AC-H1's reconcile. The `isMine` guard in the delete use case is a
  trust boundary — extend it explicitly (`isMine || (isGuest && isSpaceOwner)`), don't bypass it.

### AC-020 — `ClipSpaceRepository`: public-DB read path · agent
- **Scope**: In `ReflectClip/Data/`:
  - `ClipSpaceRepository.swift` (+ protocol): CloudKit **public** DB via
    `CKContainer(identifier: "iCloud.xyz.nandamochammad.Reflect").publicCloudDatabase`;
    `fetchRequest(token:) async throws -> ClipRequest` (lookup `MirroredRequest` by Queryable
    `requestToken`, decode `questionsJSON` into shared `SpaceQuestion`),
    `fetchAnswers(token:) async throws -> [SpaceAnswer]` (query `MirroredAnswer`, group by
    `questionId`, `answerIndex` order, map to the shared `SpaceAnswer` entity with
    `isMine = (guestId == ours)`). In-memory cache only.
  - `ClipSpaceError: Error, LocalizedError`: `.invalidLink` (no MirroredRequest → revoked/expired),
    `.network`, `.iCloudUnavailable`, `.malformedData`.
  - `extension ClipDIContainer { makeClipSpaceRepository() }` in this file (per AC-002 convention).
- **Depends on**: AC-002, AC-010 (ClipMirrorSchema)
- **Acceptance**: `ReflectClip` builds green; zero SwiftData/`SpaceCloudService`/full-app-DI
  references (purity grep); errors typed, no `try?`; decoding tolerates unknown JSON keys;
  committed. Live fetch verified on simulator after AC-H1 + one AC-011 publish.
- **Watch-outs**: Public-DB `CKQuery` needs the Queryable indexes from AC-H1 — a
  "not marked queryable" error at runtime means Console config, not code. Anonymous (no-iCloud)
  users CAN read public DB — do not gate reads on account status; only surface
  `.iCloudUnavailable` if CloudKit itself errors that way.

### AC-012 — Pending-feedback ingestion (owner's app, auto-post) · agent
- **Scope**: New `Reflect/Services/Space/SpaceClipIngestService.swift` (+ error enum), hooked from
  the same sync tail as AC-011 (re-acquires the `SpaceCloudService.swift` lock):
  - For each owned tokenized request: query `PendingClipFeedback` by `requestToken`; for each
    pending record, create an `Answer` in the shared zone with recordName
    `"guest-" + submissionId` (derived from the pending `recordName`'s `pcf-` suffix — the
    idempotency key), correct `questionId`, next `answerIndex` for that `guestId`+`questionId`,
    `guestId`/`guestName` fields set, parent = the reflection record; then delete the pending
    record. **Save-Answer-then-delete-pending, two operations in that order** — a crash between
    them re-ingests idempotently (record-exists error → treat as success → delete pending).
  - Body re-validation (length caps, questionId ∈ questionsJSON) — never trust the endpoint alone.
  - Auto-post per Decision 1: no approval UI. `DIContainer` factory (lock: after AC-011).
- **Depends on**: AC-010, AC-011 (lock order)
- **Acceptance**: build green; idempotency demonstrated at code-review level (deterministic
  recordName + exists-tolerant save); pending deletion only after Answer save succeeds; ingestion
  failure of one record doesn't abort the batch; committed. E2E verified in AC-H4.
- **Watch-outs**: `PendingClipFeedback` lacks world-read; the owner reads it as an authenticated
  user — AC-H1's role grants (+3 already exist in Production for this type) are what make this
  work; verify Dev matches. `answerIndex` must be computed against BOTH existing shared-zone
  answers and already-ingested-this-batch ones.

### AC-021 — `ClipFeedbackSubmitter` + offline queue + optimistic store · agent
- **Scope**: In `ReflectClip/Data/`:
  - `ClipFeedbackSubmitter.swift` (+ protocol): plain `URLSession` POST to
    `https://nandamochammad.xyz/clip-feedback.php` using the shared DTOs from
    `ClipMirrorSchema.swift`; mints one `submissionId` (UUID) per answer **at compose time, kept
    stable across retries**; maps HTTP 404/410 → `.linkRevoked`, 429 → `.rateLimited`, else
    `.network`.
  - `PendingAnswerStore.swift`: App Group persistence (JSON file or UserDefaults) of submitted
    answers `{submissionId, questionId, body, submittedAt, state: .queued/.sent}` — the source
    for the optimistic echo (AC-031/032) and the offline retry queue (retry on launch/foreground;
    exponential backoff; drop `.sent` entries once a `MirroredAnswer` with our `guestId` +
    matching `questionId` appears in a fetch).
  - `extension ClipDIContainer` factories in these files.
- **Depends on**: AC-002, AC-010, AC-015 (endpoint contract)
- **Acceptance**: `ReflectClip` builds green; retry reuses the SAME submissionId (assert in code
  review — this is the idempotency contract); queue survives relaunch (App Group, not memory);
  purity gate clean; committed. Live POST verified after AC-H2.
- **Watch-outs**: Don't clear queued answers on `.linkRevoked` silently — surface state so the UI
  can explain. App Group container in the Clip requires the entitlement from AC-001.

### AC-030 — Name-capture alert + session gating · agent
- **Scope**: `ReflectClip/Features/Identity/GuestNamePrompt.swift` (alert/sheet with a single
  text field: trimmed, non-empty, ≤ 50 chars — same cap as the endpoint) and wiring in
  `App/ClipRootView.swift` (this ticket holds that file's lock): `.needsName` phase shows the
  prompt before the composer is usable; saved via `GuestIdentityStore`; re-open skips it;
  "Edit name" affordance available later from the composer toolbar (stub action here, surfaced
  properly in AC-031).
- **Depends on**: AC-002
- **Acceptance**: builds green; first-launch shows prompt, relaunch doesn't (App Group/keychain);
  empty/whitespace name can't be saved; VoiceOver label on the field; committed.
- **Watch-outs**: Keep validation copy consistent with the full app's name validation tone.

### AC-014 — Share-a-request link + full-app universal-link resolution · agent
- **Scope**: Full-app side (holds the CloudSharingView/SpaceInviteInbox/AppDelegate locks):
  - Share flow: from the thread's share affordance (locate the current share entry point in
    `Presentation/Features/Space/`), owner shares a **feedback request** → calls
    `ensureRequestToken` (AC-010) + triggers a mirror publish (AC-011) → share sheet offers
    `https://nandamochammad.xyz/f/<token>` (alongside/instead of the raw CKShare URL —
    `Share/CloudSharingView.swift` and its presenter).
  - Universal link handling: `Reflect/App/AppDelegate.swift` (or scene equivalent) +
    `Reflect/App/SpaceInviteInbox.swift`: on `/f/<token>` open, `records/lookup`-equivalent fetch
    of `TokenIndex` (`tok-<token>`) from the public DB → CKShare URL → existing
    `AcceptSpaceInviteUseCase`/`SpaceInviteInbox` path → deep-link to that request's thread.
    Unknown token → friendly alert. `DIContainer` factory additions (lock: after AC-012).
- **Depends on**: AC-010, AC-011 (publish call), AC-012 (DIContainer lock order)
- **Acceptance**: build green; sharing a request produces the wrapper URL; simulating an open via
  `xcrun simctl openurl` (custom-scheme test hook) resolves a seeded token; already-member open
  deep-links to the thread without re-accepting; committed. Real AASA-routed opens verified AC-H4.
- **Watch-outs**: Do not break the existing per-Space CKShare invite path — the per-request link
  is additive. `SpaceInviteInbox.swift` is only 30 lines; keep its contract, extend beside it.

### AC-031 — "Your Feedback" composer screen (Clip landing) · agent · **HIGH RISK**
- **Scope**: `ReflectClip/Features/Compose/ClipYourFeedbackViewModel.swift` + `ClipYourFeedbackView.swift`
  mirroring `SpaceThreadView` (reference only): request header (title/note/thumbnail), one
  composer per question (1–5 from `questionsJSON`), per-question char counter, submit-all button;
  states: loading, `.invalidLink` full-screen message, network-error retry, empty questions
  fallback. On submit: `ClipFeedbackSubmitter` → persist to `PendingAnswerStore` → session phase
  → `.allFeedback`; failure keeps text, shows retry (queued state honest: "will send when
  online"). Edit-name toolbar affordance (from AC-030 stub). Updates `ClipRootView.swift`
  (holds its lock this wave) to route `.compose` here. `extension ClipDIContainer` factory.
- **Depends on**: AC-020, AC-021, AC-030
- **Acceptance**: `ReflectClip` builds green; simulator E2E with a seeded/live token: land →
  compose → submit (or queue offline) → transitions to All-feedback; text never lost on failure;
  VoiceOver labels; no hardcoded colors (token files only); purity gate; committed.
- **Watch-outs**: The optimistic-echo state machine (queued vs sent vs confirmed) is the
  design-critical mitigation from the plan — model it as an enum on the stored answer, not bools.

### AC-032 — "All feedback" screen with pending merge · agent
- **Scope**: `ReflectClip/Features/AllFeedback/ClipAllFeedbackViewModel.swift` +
  `ClipAllFeedbackView.swift` + `ClipAnswerBubble.swift`, mirroring `SpaceAllResponsesView` /
  `AnswerBubble` (reference only): question segmented picker (>1 question), answers grouped by
  question in `answerIndex` order, bylines per answer; **merge `PendingAnswerStore` entries** as
  own-answer bubbles in "Sending…"/"Waiting for the owner to sync" style until a `MirroredAnswer`
  with our `guestId`+`questionId` confirms, then drop the local copy (store API from AC-021);
  pull-to-refresh; footer note explaining delivery timing (Decision: honest copy per plan
  review). Report affordance (`mailto:` like the app's `ReportContentButton`, reimplemented
  Clip-side). `extension ClipDIContainer` factory.
- **Depends on**: AC-031
- **Acceptance**: builds green; with a live mirror: others' answers render grouped/ordered; own
  pending answer renders in pending style and survives relaunch; confirmed answers deduplicate
  (no double bubble); purity gate; committed.
- **Watch-outs**: Dedup key is `guestId`+`questionId`+text-match is WRONG — match on
  `guestId`+`questionId` count/`sourceAnswerRecordName` mapping per AC-021's store contract.

### AC-051 — Submission collateral: App Review notes, privacy label, UGC doc · agent
- **Scope**: New `docs/features/app-clip-appreview-notes.md`: the four UGC-1.2 mechanisms
  (report, owner delete of guest answers, token revocation as block, invite-only unguessable
  links), demo instructions with a placeholder for the working demo token (AC-H5 fills it),
  privacy nutrition-label delta (Clip collects display name + UGC; no tracking), and the
  data-flow diagram in prose (Clip → PHP → PendingClipFeedback → owner ingest). Update
  `docs/features/app-clip-plan.md` Phase 5.5 row with a pointer (fenced edit, this file's lock).
- **Depends on**: AC-012, AC-030 (describes shipped behavior)
- **Acceptance**: doc complete enough to paste into App Store Connect review notes; committed.

### AC-040 — `SKOverlay` upsell + install continuity · agent
- **Scope**:
  - Clip: present `SKOverlay` (`.appClip` config) after the first successful submit — trigger
    from All-feedback appear when `PendingAnswerStore` transitioned ≥1 answer to sent and no
    overlay shown yet (App Group flag). File: `ReflectClip/Features/AllFeedback/` (holds that
    folder's lock after AC-032).
  - Full app: on first launch after Clip-driven install (keychain `guestId` + App Group pending
    state present, `/f/<token>` last-token stored), run the AC-014 token-resolution flow
    automatically and surface the thread; migrate the guest name as a default `MemberProfile`
    display name suggestion. Files: `Reflect/App/SpaceInviteInbox.swift` + `AppDelegate.swift`
    (lock: after AC-014).
- **Depends on**: AC-014, AC-032
- **Acceptance**: builds green both schemes; overlay fires once (flag persisted); full-app
  cold-start with seeded App Group state auto-opens the accept flow; committed. Real
  Clip→install→app handoff verified in AC-H4.
- **Watch-outs**: `SKOverlay` no-ops in simulator — acceptance is code-level + AC-H4.

### AC-033 — Final Clip polish, accessibility, size + purity audit · agent
- **Scope**: Closing gate across `ReflectClip/` (may touch any Clip file — runs solo):
  visual pass against the app's design tokens (no hardcoded colors — grep), VoiceOver labels on
  all interactive elements, Dynamic Type spot-check, error-copy consistency; App Thinning size
  report (`xcodebuild -exportArchive` thinning report or size read from a Release build) asserted
  < 10 MB working budget; full purity grep gate; both schemes build green; delete-test reasoning
  (removing `ReflectClip/` + `ClipShared` membership returns the app to pre-Clip state).
- **Depends on**: AC-031, AC-032, AC-040 (all Clip UI merged)
- **Acceptance**: audit evidence pasted in PR; both builds green; committed.

### AC-H2 — HUMAN GATE: deploy endpoint + landing page to cPanel · human
- **Scope**: Upload `scripts/server/clip-feedback.php` + `config.php` (filled from
  `config.example.php`) + `f/` to the web root (`/home/sesirkel/nandamochammad.xyz/nandamochammad`
  — NOT `public_html`); key stays at `/home/sesirkel/nandamochammad.xyz/cloudkit-key.pem`; run the
  curl checks from AC-015's README (happy path, bad token, retry-idempotency) against **Dev**
  environment config; confirm `/f/TESTTOKEN` serves the landing page with the Smart App Banner
  meta.
- **Depends on**: AC-015, AC-016, AC-H1 (types exist in Dev) · **Blocks**: AC-021 live verify, AC-H4.
- **Acceptance**: human replies "H2 done" with curl outputs.

### AC-H3 — HUMAN GATE: CloudKit schema Dev→Production deploy (Clip additions) · human
- **Scope**: CloudKit Console → Deploy Schema Changes: `MirroredRequest`, `MirroredAnswer`,
  `TokenIndex` (+ indexes + role grants), `SpaceReflection.requestToken`,
  `Answer.guestId`/`guestName`. Verify the diff shows ONLY additions (Production is append-only —
  shapes are final after this; any later field change repeats this gate). Flip the endpoint
  `config.php` environment to `production` afterwards (coordinate with AC-H2 host access).
- **Depends on**: AC-010, AC-011, AC-012 merged (record shapes final) · **Blocks**: AC-H5.
- **Acceptance**: "H3 done"; Production console shows the new types/fields.

### AC-H4 — HUMAN GATE: on-device Local Experience two-device E2E · human (agent assists)
- **Scope**: Two physical devices (owner device + clean invitee device without Reflect):
  Settings ▸ Developer ▸ Local Experiences + Associated Domains Development (AASA CDN cache);
  verify (i) AASA resolves for the Clip App ID (Phase 4.1 remainder), (ii) the deferred
  Phase 0.3 on-device half: public-DB read-only entitlement + `CKQuery` perf in the Clip,
  (iii) full flow: link → Clip card → name alert → compose → submit → All feedback with pending
  bubble → owner device syncs → ingestion posts the Answer → guest byline + owner delete
  affordance in the full app → Clip fetch confirms and drops the pending copy, (iv) failure
  modes: airplane-mode submit (queues, retries), revoked token mid-session, deleted request,
  (v) SKOverlay → install → continuity into the accept flow, (vi) same link on a device WITH
  Reflect → full app accept + thread deep-link.
- **Depends on**: AC-033, AC-040, AC-H1, AC-H2 · **Blocks**: AC-H5.
- **Acceptance**: all six items pass on hardware; findings filed for a fix round before AC-H5.

### AC-H5 — HUMAN GATE: TestFlight E2E + App Store submission prep · human
- **Scope**: TestFlight build (Clip invocation URL testing) against **Production** schema
  (AC-H3 done, endpoint config flipped); App Store Connect: default + advanced App Clip
  experience for `https://nandamochammad.xyz/f/*`, Clip card metadata (title/subtitle/header
  image, action "View"); privacy nutrition labels per AC-051; paste review notes + mint a real
  demo token into AC-051's doc; submit.
- **Depends on**: AC-H3, AC-H4, AC-051.
- **Acceptance**: TestFlight two-device E2E green on Production; submission checklist complete.

---

## Execution waves (max 3 concurrent agent tickets; worktrees from `develop`)

| Wave | Parallel lanes (≤3 agents) | Notes | Human in parallel |
|---|---|---|---|
| 1 | **AC-001** ∥ **AC-015** ∥ **AC-016** | Disjoint: pbxproj+ReflectClip / server endpoint / server landing page. AC-001 is the only pbxproj toucher ever. | **AC-H1** (portal + Console Dev + working-tree reconcile) |
| 2 | **AC-002** ∥ **AC-010** | Disjoint: ReflectClip app files / full-app Services+Entities+ClipShared. | **AC-H2** after wave 1 merges + H1 done |
| 3 | **AC-011** ∥ **AC-013** ∥ **AC-020** | Disjoint: new mirror service (+SpaceCloudService hook lock) / Thread presentation files / ReflectClip data. | — |
| 4 | **AC-012** ∥ **AC-021** ∥ **AC-030** | Disjoint: ingest service (+SpaceCloudService re-lock, DIContainer after AC-011) / ReflectClip submit+store / ClipRootView+name prompt. | — |
| 5 | **AC-014** ∥ **AC-031** | Disjoint: full-app share/link files / ReflectClip compose (+ClipRootView lock after AC-030). Third slot intentionally empty — no conflict-free candidate. | — |
| 6 | **AC-032** ∥ **AC-051** | Disjoint: ReflectClip AllFeedback / docs. | — |
| 7 | **AC-040** solo | Touches both AllFeedback (after AC-032) and SpaceInviteInbox/AppDelegate (after AC-014) — no safe partner. | — |
| 8 | **AC-033** solo | Closing audit; may touch any ReflectClip file. | **AC-H3** (Production deploy) once 8 merges |
| 9 | — (agent pipeline STOPS here) | Hand off to human. Agents return for a fix round on AC-H4 findings. | **AC-H4** → fix round → **AC-H5** |

**Agent pipeline stop point:** after wave 8 merges, everything remaining is human-gated
(hardware, server access, Console, App Store Connect). The orchestrator hands off with the AC-H4
checklist and stands by for a findings-driven fix wave.

## Shared-file locks (orchestrator MUST enforce — one ticket at a time, in this order)

| File / area | Serial order (only these tickets may touch it) |
|---|---|
| `Reflect.xcodeproj/project.pbxproj` | **AC-001 only** (human-gate Xcode fallout reconciled at review, never by executors) |
| `ReflectClip/App/ReflectClipApp.swift` | AC-001 → AC-002 |
| `ReflectClip/App/ClipRootView.swift` | AC-002 → AC-030 → AC-031 |
| `ReflectClip/App/ClipDIContainer.swift` | AC-002 only (later factories = `extension ClipDIContainer` in feature-owned files) |
| `ReflectClip/Data/*` | AC-020 (`ClipSpaceRepository`) ∥-safe with AC-021 (`ClipFeedbackSubmitter`, `PendingAnswerStore`) only because they are different files in different waves' creation — creation order AC-020 (W3), AC-021 (W4); no shared file |
| `ReflectClip/Features/AllFeedback/*` | AC-032 → AC-040 → AC-033 |
| `ReflectClip/**` (any file, audit) | AC-033 last, solo |
| `Reflect/ClipShared/ClipMirrorSchema.swift` | **AC-010 creates; read-only for everyone after** |
| `Reflect/Services/Space/{SpaceRecord,SpaceCloudService,SpaceCloudServiceProtocol}.swift` | AC-010 → AC-011 (hook) → AC-012 (hook) |
| `Reflect/Services/Space/SpaceMirrorService.swift` | AC-011 only |
| `Reflect/Services/Space/SpaceClipIngestService.swift` | AC-012 only |
| `Reflect/Domain/Entities/Space/*` + `Reflect/Data/Space/*` | AC-010 only |
| `Reflect/App/DIContainer.swift` | AC-011 → AC-012 → AC-014 (strict) |
| `Reflect/Presentation/Features/Space/Thread/*` (+ `SpaceAuthor`, `SpaceThreadViewModel`) | AC-013 only |
| `Reflect/Presentation/Features/Space/Share/CloudSharingView.swift` | AC-014 only |
| `Reflect/App/{AppDelegate,SpaceInviteInbox}.swift` | AC-014 → AC-040 |
| `scripts/server/clip-feedback.php`, `config.example.php`, `README.md` | AC-015 only |
| `scripts/server/f/*` | AC-016 only |
| `docs/features/app-clip-plan.md` | AC-051 only (pointer edit) |

## Human gates — UNMISSABLE

| Gate | What ONLY the human can do | Blocks |
|---|---|---|
| **AC-H1** | Clip App ID + profiles; CloudKit Console Dev types/fields/indexes/roles; server + Desktop housekeeping; commit the dirty working tree | Runtime verification of AC-010/011/012/020; AC-H2 |
| **AC-H2** | Upload endpoint + landing page to cPanel; live curl verification | AC-021 live verify; AC-H4 |
| **AC-H3** | Deploy new schema to **Production**; flip endpoint env | AC-H5 (TestFlight talks to Production) |
| **AC-H4** | Two-device Local Experience E2E incl. AASA/entitlement on-device validation (Phase 0.3 remainder + Phase 4.1 remainder), failure modes, install continuity | Ship decision; AC-H5 |
| **AC-H5** | TestFlight + App Store Connect experiences + submission | Release |

Tickets whose acceptance splits **build-green (agent) vs hardware/server-verified (human)**:
AC-010, AC-011, AC-012, AC-014, AC-015, AC-020, AC-021, AC-031, AC-032, AC-040 — "build green"
on these is NOT "done done"; the orchestrator tracks both bits.

## How the waves compose

Wave 1 lays the two independent foundations at once: the Xcode target (the single scary pbxproj
edit, isolated so nothing else can conflict with it) and the entire server side (pure new files,
no Xcode dependency), while the human unblocks the portal/Console in parallel. Wave 2 builds the
two "vocabulary" layers — Clip session/identity and the full-app schema plumbing including the
shared `ClipMirrorSchema` contract file — which every later ticket consumes read-only. Wave 3
fans out three independent consumers of that vocabulary (mirror publisher, full-app guest
rendering, Clip reader); wave 4 fans out three more (ingestion, submitter/queue, name prompt).
Waves 5–7 narrow as real coupling appears: compose screen needs reader+submitter+prompt; link
sharing holds the full-app shared-surface locks; All-feedback needs compose's store contract;
SKOverlay/continuity touches both sides so it runs solo. Wave 8 is the solo closing audit. The
agent pipeline stops there: schema Production deploy, two-device Local Experience testing, and
TestFlight/submission are irreducibly human, with one agent fix-round budgeted between AC-H4 and
AC-H5. Net: 17 agent tickets, 12 of which run with at least one parallel partner; the pbxproj,
`SpaceCloudService`, `DIContainer`, and `ClipRootView` locks are the only forced serial chains.
