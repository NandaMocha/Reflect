# App Clip Plan — "Reflect Clip" (Shared Space Feedback)

Status: **Planned, not started.** Written 2026-08-04; **revised 2026-08-05** (flow decided, schema re-based on `Answer`/`questionsJSON`, Phase 0.3 desk-half done, Phase 0.4 decided). Gated on the Space feature shipping (see [space-progress.md](space-progress.md)).

## Goal — the decided flow

An App Clip invoked from a **feedback-request** link that lets a visitor, without installing the full app:

1. **Land directly on "Your Feedback"** — the composer for one feedback request (not a Space reflection list).
2. **Be asked for a name on first open**, via an alert. That name *is* the guest's identity for the session and for anything they post; it persists in the App Group/keychain so a re-open doesn't re-ask.
3. **Answer the request's questions** (1–5 per request) and submit.
4. **Then see "All feedback"** — every member's answers on that request, matching the full app's write-yours-before-you-see-others gate.

Then upsell installing the full app via `SKOverlay`.

This mirrors the full app's existing pair of screens: `Presentation/Features/Space/Thread/SpaceThreadView.swift` ("Your feedback" composer) and `Thread/SpaceAllResponsesView.swift` ("All feedback"), with `Thread/AnswerBubble.swift` as the row. The Clip reimplements these against a Clip-local repository — it must not import them (they drag in `DIContainer` and SwiftData).

**Consequence — the link is per-request, not per-Space.** Because the Clip opens on one request's composer, the token must resolve to a single `SpaceReflection`, so the link is minted when a specific feedback request is shared. This replaces the earlier per-Space `spaceToken` design and reshapes tasks 2.1 and 2.3.

## Platform constraints that shape the design

- **App Clips can only read CloudKit's public database** — no writes, no access to the private or shared database at all ([WWDC22: What's new in App Clips](https://developer.apple.com/videos/play/wwdc2022/10097/), [Apple forums](https://developer.apple.com/forums/thread/658307)). The Clip can never open a `CKShare` or read the Space's shared zone directly. **Re-verified 2026-08-05: unchanged.** Apple states the write restriction is deliberate — it keeps the promise that when an App Clip stops being used, iOS deletes the Clip and its data — so it is not a gap likely to close. The write path below is therefore mandatory, not a workaround for a temporary limitation.
- **CKShare URLs live on `icloud.com`**, where you can't host an `apple-app-site-association` (AASA) file. The Clip can only be invoked from a domain you control, so the share flow needs a wrapper link (`https://yourdomain.com/f/<token>`) instead of the raw CKShare URL.
- **The App Group SwiftData caches are not usable for this.** `SpaceStore` and the main app's store are deliberately `groupContainer: .none` (local-only), by design, to avoid the known App Group store-collision bug and keep CloudKit as source of truth. A Clip can't read them, and an App Group container is only populated once the full app is installed anyway — at which point the invite link should route to the full app, not the Clip.

## Recommended architecture: public-DB mirror + thin write endpoint

1. **Read path — public DB mirror.** When the owner's full app syncs a Space it owns, it additionally publishes a sanitized read model to the CloudKit **public** database: `MirroredRequest` (one feedback request: title, note, thumbnail, and its `questionsJSON`) plus `MirroredAnswer` records (one per member per question, carrying `questionId`, `answerIndex`, author display name, and body), keyed by an unguessable `requestToken` (128-bit random, embedded in the link). The Clip queries the public DB directly, maps records to the existing Domain entities under `Reflect/Domain/Entities/Space/`, and holds them **in memory only** — no SwiftData in the Clip target.
2. **Write path — PHP endpoint on existing cPanel hosting (IN SCOPE, decided 2026-08-05).** A small PHP script (using the `openssl` extension, present in standard cPanel PHP stacks) signs and calls CloudKit Web Services with a server-to-server key to create a `PendingClipFeedback` public record — one per answered question, carrying `requestToken`, `questionId`, `guestId`, `guestName`, and body. The owner's full app ingests pending records during its normal sync and re-posts them into the shared zone as real `Answer` records attributed to the guest, then deletes the pending record. CloudKit stays the single source of truth; nothing but full-app participants ever writes to the shared zone.
3. **Guest identity.** The full app keys authorship on `memberRecordName` via `MemberProfile` records — a CloudKit user record the Clip does not have. The Clip therefore synthesizes one: a UUID `guestId` minted on first launch and stored in the keychain, paired with the display name from the first-open alert. Ingestion (2.6) writes a `MemberProfile`-equivalent attribution so guest answers render with a name like any other member's, marked as a guest. Keychain storage means the identity survives into the full app on install.
4. **Full app link resolution.** A `TokenIndex` public record maps `requestToken` → CKShare URL + reflection ID, so when the same universal link opens the **full app** (already installed, or just installed via the Clip's upsell), the app resolves the token, runs the existing `AcceptSpaceInviteUseCase` / `SpaceInviteInbox` flow, and deep-links to that request's thread.
5. **Clip-local persistence.** Guest name, `guestId`, and submitted-but-unconfirmed answers live in the shared App Group container / keychain, which migrate to the full app on install for clean handoff.

**No read-only descope.** The earlier plan kept "read-only + upsell" as an MVP lever. The decided flow is *centred* on the guest leaving feedback, so tasks 2.5/2.6 are load-bearing and cannot be deferred without deleting the feature's purpose.

### The submit→see-others gap (design-critical)

The guest's own answer takes a long round trip before it exists in the mirror: Clip → PHP → `PendingClipFeedback` → **the owner's app must next open and sync** → re-post as `Answer` → next mirror publish. Since the decided flow sends the guest from "Your Feedback" straight to "All feedback", a naive implementation shows them a page that is missing the answer they just wrote — potentially for days, since it waits on the owner opening the app.

Mitigation, and it is mandatory rather than polish: the Clip keeps its submitted answers in the App Group and **merges them optimistically** into "All feedback", rendered as its own bubble in a pending style ("Sending…"), until a mirror fetch contains a matching `MirroredAnswer` for that `guestId` + `questionId`, at which point the local copy is dropped in favour of the server one. Task 3.2 owns this.

**Clip target layering:** its own `ClipDIContainer` (mirrors `DIContainer.shared`'s factory style), `@Observable @MainActor final` ViewModels, a `ClipSpaceRepository` + `ClipFeedbackSubmitter` in a Clip-local Data layer, and shares Domain entity files from `Reflect/Domain/Entities/Space/` via target membership (no duplication). Must NOT compile in `SpaceStore`, the `Cached*` models, or `SpaceCloudService` (all assume private/shared DB access).

## Hosting: cPanel is sufficient

The user's existing domain + cPanel hosting covers both hosting needs.

**Status: hosting VERIFIED on `nandamochammad.xyz` (2026-08-05).** Preflight passed on every check, including outbound HTTPS to `api.apple-cloudkit.com` — so the write endpoint can live on this cPanel; no Cloudflare Worker/Vercel fallback needed. The AASA file is **deployed and serving** (see 4.1 below). Host specifics worth remembering:

- **Web root is `/home/sesirkel/nandamochammad.xyz/nandamochammad`**, NOT `public_html` (addon-domain layout). Uploading to `public_html` silently targets a different domain on the account.
- **Store the CloudKit `.pem` in `/home/sesirkel/nandamochammad.xyz/`** — writable, above the web root, not web-reachable.
- Server is **LiteSpeed** (honours `.htaccess`) and assigns content-type **by file extension**, while sending `x-content-type-options: nosniff`. Since the AASA file deliberately has no extension, the `ForceType application/json` rule in `.well-known/.htaccess` is **required**, not optional.
- `www` → apex 301, and Apple's fetcher does not follow redirects, so the **apex** (`nandamochammad.xyz`) is what belongs in the `appclips:` entitlement. Let's Encrypt cert SAN covers the apex explicitly (the wildcard CN alone would not have).

**Re-run the preflight if the host ever changes:** [`scripts/appclip-hosting-preflight.php`](../../scripts/appclip-hosting-preflight.php) — upload to the web root, open in a browser, read the verdict, then delete it. It proves PHP/openssl can do ECDSA P-256 + SHA-256 signing, that cURL is present, and — the make-or-break check — that the host actually permits **outbound HTTPS to `api.apple-cloudkit.com`**. Budget shared hosts sometimes block outbound PHP connections entirely, which makes a CloudKit proxy impossible there at any price; the fallback is to host the endpoint on Cloudflare Workers/Vercel and keep the domain purely for AASA.

Two further things to verify before wiring the entitlement:

1. **AASA file at `public_html/.well-known/apple-app-site-association`** (no extension, valid JSON, served as `application/json`/`text/plain`).
   - Check `.well-known/` isn't blocked by security plugins/ModSecurity: `curl -I https://yourdomain.com/.well-known/apple-app-site-association` must return `200`.
   - Apple's fetcher does **not** follow redirects — the AASA must be reachable at the exact host used in the `appclips:` entitlement with no forced `www` redirect on that path.
   - Needs a valid HTTPS cert (cPanel AutoSSL/Let's Encrypt is fine).
2. **PHP write endpoint** (only if the write path is in scope): store the CloudKit Web Services private key **outside `public_html`** (or blocked via `.htaccess`), never in a web-reachable path. Add basic rate limiting (token + IP throttling) in the script itself, since shared hosting has no platform-level WAF. CloudLinux-based hosts cap CPU/processes per account — fine for a small user base, not built for a traffic spike.

The `/f/<token>` invite-link page (web fallback + Smart App Banner trigger) is a plain PHP/HTML page — trivial on cPanel.

## Phase 0 — Prerequisites & decisions (GATING)

| # | Task | Effort | Depends on |
|---|------|--------|-----------|
| 0.1 | **Space feature stabilization (H2–H5)** — two-device hardware verification, CloudKit schema Dev→Production, TestFlight E2E; push the ~90 local commits to origin | 2–4 days (already tracked separately) | — |
| 0.2 | ~~Hosting decision~~ **Resolved: existing domain + cPanel hosting will be used.** | — | — |
| 0.3 | **Architecture spike:** scratch App Clip project confirming (i) CloudKit read-only public-DB entitlement works against `iCloud.xyz.nandamochammad.Reflect`, (ii) `CKQuery` by `requestToken` performs acceptably, (iii) writes correctly fail. **Desk half DONE 2026-08-05** — Apple's read-only rule re-verified as current and deliberate; the on-device half still stands | 0.25 day (was 0.5) | — |
| 0.4 | ~~Scope decision~~ **Resolved 2026-08-05: full write path (PHP endpoint) is in scope.** The decided flow is built around the guest posting feedback, so read-only is not a viable descope | — | — |
| 0.5 | **Portal setup:** App Clip App ID (`xyz.nandamochammad.Reflect.Clip`), App Clip entitlement profile, Associated Domains capability; generate the CloudKit Web Services server-to-server key (now required — 0.4 chose the write path) | 0.5 day | — |

**Parallelism:** App Clip Phases 1–3 can start **in parallel** with Space stabilization once H2 (two-device verification) passes — Clip correctness depends on the sync engine being sound, not on TestFlight being done. Don't start Phase 2's mirror schema work until H4 (schema Dev→Production) is planned, so the mirror record types ride the same schema deployment. Phase 5 (TestFlight/submission) is hard-blocked on H4/H5.

## Phase 1 — Target scaffolding (0.5–1 day)

| # | Task | Effort | Depends on |
|---|------|--------|-----------|
| 1.1 | Add `ReflectClip` App Clip target; entitlements: parent application identifier, `com.apple.developer.associated-domains` (`appclips:<domain>`), CloudKit container, App Group `group.xyz.nandamochammad.Reflect` | 2–3 h | 0.5 |
| 1.2 | `ClipDIContainer` skeleton + `ReflectClipApp.swift` with `onContinueUserActivity(NSUserActivityTypeBrowsingWeb)` stub parsing `requestToken` from the URL; `_XCAppClipURL` environment variable set in the scheme for local testing | 2 h | 1.1 |
| 1.3 | Share Domain entity files + Color/Constants tokens into the Clip target via target membership; add a minimal Clip asset catalog (accent color, app clip icon only). Verify no `SpaceStore`/SwiftData/`DIContainer` files leak into the Clip target | 2 h | 1.1 |
| 1.4 | Build both targets green with xcodebuild; check baseline Clip size via App Thinning size report | 1 h | 1.3 |

**Acceptance:** three targets build green; Clip launches in simulator from `_XCAppClipURL` and logs the parsed token; baseline thinned Clip size recorded (target ~1–2 MB, working budget 10 MB).

## Phase 2 — Data layer (3.5–5.5 days)

Full-app side:

| # | Task | Effort | Depends on |
|---|------|--------|-----------|
| 2.1 | **`requestToken` generation (per feedback request, not per Space):** random token minted when a request is shared, stored on the `SpaceReflection` CloudKit record + `CachedSpaceReflection`; `TokenIndex` public record (token → CKShare URL + reflection ID). Requires a new field on `SpaceReflection` — must ride the same schema deploy as H4 | 0.5 day | 1.4, H2 |
| 2.2 | `SpaceMirrorService` (new, `Reflect/Services/Space/`): after each successful `fetchChanges`/local write for a Space the user **owns**, upsert `MirroredRequest` (incl. `questionsJSON`) + `MirroredAnswer` public records for any tokenized request; delete mirror on request/space deletion or share revocation. Domain-specific `SpaceMirrorError` enum, no silent `try?`. Mirrors the multi-question shape: N answers per question per member, preserving `answerIndex` | 1.5–2 days (was 1–1.5; multi-question inflates it) | 2.1 |
| 2.3 | Share-a-request link: sharing a feedback request produces `https://yourdomain.com/f/<token>`; full-app universal link handler resolves token → CKShare URL → existing `SpaceInviteInbox`/`AcceptSpaceInviteUseCase` path, then deep-links to that request's thread. Update `CloudSharingView.swift` and scene/AppDelegate handling | 1–1.5 days | 2.1 |

Clip side:

| # | Task | Effort | Depends on |
|---|------|--------|-----------|
| 2.4 | `ClipSpaceRepository` (Clip target): fetch `MirroredRequest` + `MirroredAnswer` from the public DB by token, decode `questionsJSON`, group answers by `questionId` in `answerIndex` order, map to Domain entities, in-memory cache, `ClipSpaceError: Error, LocalizedError` (revoked/expired token, network, iCloud-unavailable) | 1.5–2 days (was 1–1.5) | 1.4, 2.2 schema |
| 2.5 | **Write path (now mandatory per 0.4). MECHANISM PROVEN 2026-08-05** — see spike note below; what remains is the production endpoint (token validation, rate limiting, error handling) plus `ClipFeedbackSubmitter` in the Clip (plain URLSession) posting `requestToken`/`questionId`/`guestId`/`guestName`/body | 1–1.5 days (was 1.5–2; signing/auth de-risked) | 0.5, 2.2 |
| 2.6 | Full-app ingestion: during Space sync, the owner's app reads `PendingClipFeedback`, re-posts each as an `Answer` record (correct `questionId`, next `answerIndex` for that guest+question) into the shared zone with guest attribution, then deletes the pending record. Idempotent on `guestId`+`questionId`+client id so a retried submission can't double-post | 1–1.5 days (was 0.5–1; multi-question + idempotency) | 2.5 |
| 2.7 | **Guest identity plumbing:** `guestId` UUID minted + keychain-stored in the Clip, name captured by the first-open alert, both persisted to the App Group; ingestion writes the guest's display name so `MirroredAnswer` bylines resolve | 0.5 day | 1.2, 2.5 |

### Write-path spike — PROVEN 2026-08-05

The CloudKit write mechanism is no longer an unknown. [`scripts/appclip-cloudkit-write-test.php`](../../scripts/appclip-cloudkit-write-test.php) ran green against the live API from the production host: signed a request with the server-to-server key, created a `PendingClipFeedback` record in the **public** database, and deleted it again (both HTTP 200). Task 2.5 is therefore ordinary engineering, not a research question.

Established by the spike, and reusable directly in the real endpoint:

- **Signing scheme:** sign `"<ISO8601 date>:<base64(sha256(body))>:<subpath>"` with ECDSA/SHA-256, send as `X-Apple-CloudKit-Request-KeyID` / `-ISO8601Date` / `-SignatureV1`. See `cloudkit_request()` in the spike script.
- **Endpoint shape:** `POST https://api.apple-cloudkit.com/database/1/<container>/<environment>/public/records/modify`.
- **Server-to-server keys CANNOT create schema.** Unlike a first write from the app, no record type is auto-created — every public record type must be defined in CloudKit Console by hand before the server can write it. This applies to `MirroredRequest`/`MirroredAnswer`/`TokenIndex` too, so budget for it in 2.2.
- **Key custody as deployed:** private key at `/home/sesirkel/nandamochammad.xyz/cloudkit-key.pem`, `0600`, above the web root and verified unreachable by URL. PHP runs as the account user, so `0600` is still readable by it.
- **`PendingClipFeedback` now exists in the Development schema** with String fields `requestToken` (Queryable), `questionId`, `guestId`, `guestName`, `body`, plus a Queryable `recordName` index — **must ride the H4 Dev→Production deploy.**

**Acceptance:** owner device publishes/updates the mirror automatically; Clip (simulator, no full app) renders a real request's questions and every member's answers for a token; feedback submitted from the Clip appears in the full app's thread on another device within one owner sync cycle, attributed to the guest name, with no duplicates on retry; revoked token yields a friendly error, not a crash; all record types and the new `SpaceReflection` token field exist in the CloudKit Dev schema and are queued for the H4 production deploy.

## Phase 3 — Clip UI (2–3 days)

| # | Task | Effort | Depends on |
|---|------|--------|-----------|
Screen order follows the decided flow: **name alert → Your Feedback → All feedback.**

| # | Task | Effort | Depends on |
|---|------|--------|-----------|
| 3.1 | **Name-capture alert:** on first launch, before the composer is usable, an alert asks for a display name (validated non-empty, trimmed, length-capped per `Constants.Limits`); persists with `guestId` to keychain/App Group and never re-asks. Editable later from the Clip's own UI | 0.5 day | 1.2, 2.7 |
| 3.2 | `ClipYourFeedbackViewModel` + `ClipYourFeedbackView` — the Clip's landing screen, mirroring `Thread/SpaceThreadView.swift`: request header (title, note, photo), one composer per question (1–5), submit-all; loading/empty/error states; **optimistic local echo** of submitted answers persisted to the App Group per the submit→see-others gap above, with retry on failure | 1.5–2 days | 2.4, 2.5, 3.1 |
| 3.3 | `ClipAllFeedbackViewModel` + `ClipAllFeedbackView` — mirrors `Thread/SpaceAllResponsesView.swift`: question segmented control, answers grouped by question in `answerIndex` order, bylines repeat per answer (no author grouping, matching the app's decision 3); merges the guest's pending local answers in "Sending…" style until the mirror confirms them. Reached after submitting, and via a toolbar button | 1–1.5 days | 3.2 |
| 3.4 | Visual polish reusing Color/Constants tokens; verify no hardcoded colors; borrow layout patterns from `Presentation/Features/Space/Thread` (incl. `AnswerBubble`) without importing full-app view files that drag in `DIContainer`/SwiftData | 0.5–1 day | 3.3 |

**Acceptance:** end-to-end in simulator via `_XCAppClipURL`: open link → name alert → Your Feedback with the request's real questions → submit → All feedback shows own answers (pending style) alongside other members' → relaunch shows the name is remembered and answers persist; builds green; VoiceOver labels on interactive elements; visual style consistent with the main app.

## Phase 4 — Invocation & upsell (1.5–2 days)

| # | Task | Effort | Depends on |
|---|------|--------|-----------|
| 4.1 | **DONE 2026-08-05 (deploy half).** AASA published at `https://nandamochammad.xyz/.well-known/apple-app-site-association` — verified `200`, `content-type: application/json`, **0 redirects**, body byte-identical to `scripts/appclip-aasa.json`, `.htaccess` itself not publicly readable (403). `.well-known/` confirmed unblocked. **Remaining:** re-validate on-device once the Clip App ID exists (0.5), since the file references an App ID not yet created; iOS caches AASA on a CDN, so use Settings ▸ Developer ▸ *Associated Domains Development* when testing | ~0.1 day left (was 0.5) | 2.3 |
| 4.2 | App Store Connect: default + advanced App Clip experience for `https://yourdomain.com/s/*`; Clip card metadata (title, subtitle, header image, action verb "View") | 0.5 day | 4.1 |
| 4.3 | `SKOverlay` upsell: shown after the first successful feedback post; on install, full app picks up keychain guest name + App Group pending state and auto-runs the token→accept-share flow so the user lands in the Space as a real participant | 0.5–1 day | 2.3, 3.2 |

**Acceptance:** tapping the invite link on a device without Reflect shows the Clip card and launches the Clip with the correct Space; same link on a device with Reflect installed opens the full app into the accept-invite flow; install-from-overlay lands the user in the Space with their guest identity migrated.

## Phase 5 — Testing & submission (2–3 days) — hard-blocked on H4/H5

| # | Task | Effort | Depends on |
|---|------|--------|-----------|
| 5.1 | Local Experiences testing on two physical devices (owner device + clean invitee device) | 0.5–1 day | Phase 4, H2 |
| 5.2 | Size audit: App Thinning report, strip unused assets/dependencies; assert < 10 MB working budget | 0.5 day | Phase 3 |
| 5.3 | Failure-mode pass: airplane mode, revoked share mid-session, deleted Space, iCloud unavailable, malformed token | 0.5 day | 5.1 |
| 5.4 | TestFlight build (App Clips are testable via TestFlight invocation URL), E2E with production CloudKit schema | 0.5 day | H4, H5, 5.1 |
| 5.5 | Submission prep: privacy nutrition label update (Clip collects a display name + UGC), App Review notes with a working demo token, UGC compliance check — guests can post content, so Apple's UGC guideline 1.2 may require a report/block affordance; verify existing Compliance work under `Presentation/Features/Space/Compliance` covers Clip-originated posts | 0.5 day | 5.4 |

**Acceptance:** two-device E2E green on TestFlight against production schema; thinned size under budget; all failure modes show recoverable UI; submission checklist complete.

## Risks & open questions

1. ~~**App Clip CloudKit rules could have shifted.**~~ **Closed 2026-08-05.** Re-verified as current and deliberate on Apple's part; the write path does not collapse and 2.5/2.6 stand as planned.
2. **Guest UGC and App Review — now a primary risk, not a secondary one.** The decided flow makes unauthenticated guest posting the whole point, so Apple's UGC guideline 1.2 expectations (reporting/blocking, moderation) apply squarely rather than incidentally. Mitigations: owner-only ingestion (2.6) is a real approval choke point — consider surfacing pending guest feedback for explicit owner approval rather than auto-posting; keep the token unguessable; server-side rate limiting; confirm `Presentation/Features/Space/Compliance` affordances cover Clip-originated content. **Decide the auto-post vs owner-approval question before building 2.6** — it changes the ingestion design.
3. **Mirror staleness cuts directly across the decided flow.** The mirror only updates when the owner's app syncs, so a guest who submits and moves to "All feedback" would see their own answer missing until the owner next opens the app. This is why the optimistic local echo in 3.2/3.3 is mandatory. Other members' newer answers may still be stale for the guest — acceptable for v1; document it in-app if the gap is visible.
4. **Server-to-server key custody.** The CloudKit web-services private key must live only outside `public_html`, never in the repo or the Clip binary.
5. **Unshipped Space feature.** Everything here rides on a feature that has never been through two-device or production-schema testing; treat H2/H4 as real gates, not formalities.
6. **Photo attachments in the Clip.** Mirroring image assets to the public DB adds cost/size; v1 can mirror thumbnails only or omit images.
7. **cPanel process/CPU limits.** CloudLinux-based shared hosts cap resources per account — fine for a small user base, but the write endpoint isn't built to survive a traffic spike.

8. **Multi-question inflation.** The plan was originally sized against a single `promptText` + flat `Response` thread. The shipped schema is `questionsJSON` (1–5 questions) + `Answer` records keyed by `questionId` with a per-member `answerIndex`. Every read/write/mirror task carries that fan-out, which is where the re-estimate below comes from.

**Total estimate:** ~14.5–19.5 working days of Clip work (originally 11–16), excluding the Space H2–H5 stabilization. The write path is no longer a descoping lever. The increase came from the multi-question schema (2.2, 2.4, 2.6, Phase 3), guest identity (2.7), and the mandatory optimistic echo; the 2026-08-05 write-path spike then took ~0.5 day back off 2.5 and, more importantly, removed the risk that the endpoint would prove unworkable on this host.

### Critical files for implementation
- `Reflect/Services/Space/SpaceCloudService.swift` — sync hooks for mirror publishing and pending-feedback ingestion
- `Reflect/Services/Space/SpaceCloudServiceProtocol.swift` — protocol additions for mirror/ingest
- `Reflect/Services/Space/SpaceRecord.swift` — `SpaceRecordType`/`SpaceRecordField` constants the mirror types must stay consistent with (`Answer`, `questionsJSON`, `reflectionID`); add the `requestToken` field here
- `Reflect/App/DIContainer.swift` — pattern to mirror in `ClipDIContainer`; new mirror-service wiring
- `Reflect/Presentation/Features/Space/Share/CloudSharingView.swift` — replace raw CKShare URL with the per-request wrapper link
- `Reflect/App/SpaceInviteInbox.swift` — full-app universal-link/token resolution into the existing accept flow
- `Reflect/Presentation/Features/Space/Thread/SpaceThreadView.swift` + `Thread/SpaceAllResponsesView.swift` + `Thread/AnswerBubble.swift` — the two screens and row the Clip reimplements (reference only; must not be imported into the Clip target)

### Sources
[What's new in App Clips — WWDC22](https://developer.apple.com/videos/play/wwdc2022/10097/) · [Apple Developer Forums: App Clips and CloudKit public database](https://developer.apple.com/forums/thread/658307) · [What's new in CloudKit — WWDC21](https://developer.apple.com/videos/play/wwdc2021/10086/)
