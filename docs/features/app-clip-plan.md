# App Clip Plan — "Reflect Clip" (Shared Space Feedback)

Status: **Planned, not started.** Written 2026-08-04. Gated on the Space feature shipping (see [space-progress.md](space-progress.md)).

## Goal

An App Clip invoked from a Space invite link that lets a visitor, without installing the full app:
- View the list of reflections in a shared Space
- Read all feedback on a reflection
- Leave feedback (if the write path is in scope — see Phase 0.4)

Then upsell installing the full app via `SKOverlay`.

## Platform constraints that shape the design

- **App Clips can only read CloudKit's public database** — no writes, no access to the private or shared database at all ([WWDC22: What's new in App Clips](https://developer.apple.com/videos/play/wwdc2022/10097/), [Apple forums](https://developer.apple.com/forums/thread/658307)). The Clip can never open a `CKShare` or read the Space's shared zone directly. Re-verify this hasn't changed on current SDKs before committing (Phase 0.3).
- **CKShare URLs live on `icloud.com`**, where you can't host an `apple-app-site-association` (AASA) file. The Clip can only be invoked from a domain you control, so the share flow needs a wrapper link (`https://yourdomain.com/s/<token>`) instead of the raw CKShare URL.
- **The App Group SwiftData caches are not usable for this.** `SpaceStore` and the main app's store are deliberately `groupContainer: .none` (local-only), by design, to avoid the known App Group store-collision bug and keep CloudKit as source of truth. A Clip can't read them, and an App Group container is only populated once the full app is installed anyway — at which point the invite link should route to the full app, not the Clip.

## Recommended architecture: public-DB mirror + thin write endpoint

1. **Read path — public DB mirror.** When the owner's full app syncs a shared Space it already owns, it additionally publishes a sanitized read model to the CloudKit **public** database: `MirroredSpace` / `MirroredReflection` / `MirroredResponse` records, keyed by an unguessable `spaceToken` (128-bit random, embedded in the invite URL). The Clip queries the public DB directly, maps records to the existing Domain entities (`Space`, `SpaceReflection`, `SpaceResponse`), and holds them **in memory only** — no SwiftData in the Clip target.
2. **Write path — PHP endpoint on existing cPanel hosting.** The user has a domain + cPanel/shared hosting already, which is sufficient (see hosting notes below). A small PHP script (using the `openssl` extension, present in standard cPanel PHP stacks) signs and calls CloudKit Web Services with a server-to-server key to create a `PendingClipFeedback` public record. The owner's full app ingests pending records during its normal sync and re-posts them into the shared zone as real `SpaceResponse` records, attributed "Guest via App Clip — <name>". CloudKit stays the single source of truth; nothing but full-app participants ever writes to the shared zone.
3. **Full app link resolution.** A `TokenIndex` public record maps `spaceToken` → CKShare URL, so when the same universal link opens the **full app** (already installed, or just installed via the Clip's upsell), the app resolves the token and runs the existing `AcceptSpaceInviteUseCase` / `SpaceInviteInbox` flow.
4. **Clip-local persistence.** Guest display name and any unsent feedback live in the shared App Group container / keychain — keychain items migrate to the full app automatically on install, enabling clean handoff.

**MVP descoping lever:** if the PHP write path proves too much for v1, ship the Clip **read-only + upsell**, and stash composed feedback in the App Group for auto-posting after install. The write endpoint is isolated as its own task (2.5) so it's easy to defer.

**Clip target layering:** its own `ClipDIContainer` (mirrors `DIContainer.shared`'s factory style), `@Observable @MainActor final` ViewModels, a `ClipSpaceRepository` + `ClipFeedbackSubmitter` in a Clip-local Data layer, and shares Domain entity files from `Reflect/Domain/Entities/Space/` via target membership (no duplication). Must NOT compile in `SpaceStore`, the `Cached*` models, or `SpaceCloudService` (all assume private/shared DB access).

## Hosting: cPanel is sufficient

The user's existing domain + cPanel shared hosting covers both hosting needs. Two things to verify before wiring the entitlement:

1. **AASA file at `public_html/.well-known/apple-app-site-association`** (no extension, valid JSON, served as `application/json`/`text/plain`).
   - Check `.well-known/` isn't blocked by security plugins/ModSecurity: `curl -I https://yourdomain.com/.well-known/apple-app-site-association` must return `200`.
   - Apple's fetcher does **not** follow redirects — the AASA must be reachable at the exact host used in the `appclips:` entitlement with no forced `www` redirect on that path.
   - Needs a valid HTTPS cert (cPanel AutoSSL/Let's Encrypt is fine).
2. **PHP write endpoint** (only if the write path is in scope): store the CloudKit Web Services private key **outside `public_html`** (or blocked via `.htaccess`), never in a web-reachable path. Add basic rate limiting (token + IP throttling) in the script itself, since shared hosting has no platform-level WAF. CloudLinux-based hosts cap CPU/processes per account — fine for a small user base, not built for a traffic spike.

The `/s/<token>` invite-link page (web fallback + Smart App Banner trigger) is a plain PHP/HTML page — trivial on cPanel.

## Phase 0 — Prerequisites & decisions (GATING)

| # | Task | Effort | Depends on |
|---|------|--------|-----------|
| 0.1 | **Space feature stabilization (H2–H5)** — two-device hardware verification, CloudKit schema Dev→Production, TestFlight E2E; push the ~90 local commits to origin | 2–4 days (already tracked separately) | — |
| 0.2 | ~~Hosting decision~~ **Resolved: existing domain + cPanel hosting will be used.** | — | — |
| 0.3 | **Architecture spike:** scratch App Clip project confirming (i) CloudKit read-only public-DB entitlement works against `iCloud.xyz.nandamochammad.Reflect`, (ii) `CKQuery` by `spaceToken` performs acceptably, (iii) writes correctly fail. Re-check current Apple docs in case this has changed | 0.5 day | — |
| 0.4 | **Scope decision:** full write path (PHP endpoint) vs MVP read-only Clip with post-install feedback handoff | 0.5 day (decide after 0.3) | 0.3 |
| 0.5 | **Portal setup:** App Clip App ID (`xyz.nandamochammad.Reflect.Clip`), App Clip entitlement profile, Associated Domains capability; generate CloudKit Web Services server-to-server key (if 0.4 chose the write path) | 0.5 day | — |

**Parallelism:** App Clip Phases 1–3 can start **in parallel** with Space stabilization once H2 (two-device verification) passes — Clip correctness depends on the sync engine being sound, not on TestFlight being done. Don't start Phase 2's mirror schema work until H4 (schema Dev→Production) is planned, so the mirror record types ride the same schema deployment. Phase 5 (TestFlight/submission) is hard-blocked on H4/H5.

## Phase 1 — Target scaffolding (0.5–1 day)

| # | Task | Effort | Depends on |
|---|------|--------|-----------|
| 1.1 | Add `ReflectClip` App Clip target; entitlements: parent application identifier, `com.apple.developer.associated-domains` (`appclips:<domain>`), CloudKit container, App Group `group.xyz.nandamochammad.Reflect` | 2–3 h | 0.5 |
| 1.2 | `ClipDIContainer` skeleton + `ReflectClipApp.swift` with `onContinueUserActivity(NSUserActivityTypeBrowsingWeb)` stub parsing `spaceToken` from the URL; `_XCAppClipURL` environment variable set in the scheme for local testing | 2 h | 1.1 |
| 1.3 | Share Domain entity files + Color/Constants tokens into the Clip target via target membership; add a minimal Clip asset catalog (accent color, app clip icon only). Verify no `SpaceStore`/SwiftData/`DIContainer` files leak into the Clip target | 2 h | 1.1 |
| 1.4 | Build both targets green with xcodebuild; check baseline Clip size via App Thinning size report | 1 h | 1.3 |

**Acceptance:** three targets build green; Clip launches in simulator from `_XCAppClipURL` and logs the parsed token; baseline thinned Clip size recorded (target ~1–2 MB, working budget 10 MB).

## Phase 2 — Data layer (3.5–5.5 days)

Full-app side:

| # | Task | Effort | Depends on |
|---|------|--------|-----------|
| 2.1 | `spaceToken` generation: random token minted at share time, stored on the Space's CloudKit record + `CachedSpace`; `TokenIndex` public record (token → CKShare URL) | 0.5 day | 1.4, H2 |
| 2.2 | `SpaceMirrorService` (new, `Reflect/Services/Space/`): after each successful `fetchChanges`/local write for a Space the user **owns**, upsert `MirroredSpace`/`MirroredReflection`/`MirroredResponse` public records; delete mirror on space deletion/share revocation. Domain-specific `SpaceMirrorError` enum, no silent `try?` | 1–1.5 days | 2.1 |
| 2.3 | Invite link wrapper: share flow produces `https://yourdomain.com/s/<token>`; full-app universal link handler resolves token → CKShare URL → existing `SpaceInviteInbox`/`AcceptSpaceInviteUseCase` path. Update `CloudSharingView.swift` and scene/AppDelegate handling | 1 day | 2.1 |

Clip side:

| # | Task | Effort | Depends on |
|---|------|--------|-----------|
| 2.4 | `ClipSpaceRepository` (Clip target): fetch mirror records from public DB by token, map to Domain entities, in-memory cache, `ClipSpaceError: Error, LocalizedError` (revoked/expired token, network, iCloud-unavailable) | 1–1.5 days | 1.4, 2.2 schema |
| 2.5 | Write path (skippable per 0.4): PHP endpoint on cPanel hosting, signs + calls CloudKit Web Services with a server-to-server key to create `PendingClipFeedback` public records; `ClipFeedbackSubmitter` in the Clip (plain URLSession); token validation + rate limiting server-side | 1.5–2 days | 0.5, 2.2 |
| 2.6 | Full-app ingestion: during Space sync, owner's app reads `PendingClipFeedback`, re-posts as `SpaceResponse` ("Guest via App Clip — <name>") into the shared zone, deletes the pending record | 0.5–1 day | 2.5 |

**Acceptance:** owner device publishes/updates the mirror automatically; Clip (simulator, no full app) lists real reflections and feedback for a token; feedback submitted from the Clip appears in the full app's thread on another device within one sync cycle; revoked token yields a friendly error, not a crash; all record types exist in the CloudKit Dev schema and are queued for the H4 production deploy.

## Phase 3 — Clip UI (2–3 days)

| # | Task | Effort | Depends on |
|---|------|--------|-----------|
| 3.1 | `ClipSpaceViewModel` + `ClipSpaceView`: Space header, reflection list (title, prompt, photo thumbnail, feedback count); loading/empty/error states | 1 day | 2.4 |
| 3.2 | `ClipThreadViewModel` + `ClipThreadView`: full feedback list on a reflection; composer (if write path in scope) with first-use guest display-name prompt (keychain/App Group); optimistic insert + failure retry | 1 day | 3.1, 2.5 |
| 3.3 | Visual polish reusing Color/Constants tokens; verify no hardcoded colors; borrow layout patterns from `Presentation/Features/Space/Thread` without importing full-app view files that drag in `DIContainer`/SwiftData | 0.5–1 day | 3.1 |

**Acceptance:** end-to-end in simulator via `_XCAppClipURL`: open link → see reflections → open thread → read feedback → (if in scope) post feedback; builds green; VoiceOver labels on interactive elements; visual style consistent with the main app.

## Phase 4 — Invocation & upsell (1.5–2 days)

| # | Task | Effort | Depends on |
|---|------|--------|-----------|
| 4.1 | Publish AASA with `appclips` (and `applinks` for the full app) on the cPanel-hosted domain; verify with the AASA validator / device developer settings; confirm `.well-known/` isn't blocked and no forced redirect on that path | 0.5 day | 2.3 |
| 4.2 | App Store Connect: default + advanced App Clip experience for `https://yourdomain.com/s/*`; Clip card metadata (title, subtitle, header image, action verb "View") | 0.5 day | 4.1 |
| 4.3 | `SKOverlay` upsell: shown after first successful feedback post (or after browsing, if read-only MVP); on install, full app picks up keychain guest name + App Group pending state and auto-runs the token→accept-share flow so the user lands in the Space as a real participant | 0.5–1 day | 2.3, 3.2 |

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

1. **App Clip CloudKit rules could have shifted.** Read-only public DB was the iOS 16 rule; Phase 0.3 re-verifies before committing to the write path. If Apple now allows public-DB writes from Clips, task 2.5 collapses to a native write and the PHP endpoint shrinks to AASA hosting only.
2. **Guest UGC and App Review.** Unauthenticated guests posting feedback may trigger UGC moderation requirements (reporting/blocking). Mitigations: owner-only ingestion (2.6) gives an implicit approval point; keep the token unguessable; server-side rate limiting.
3. **Mirror staleness.** The mirror only updates when the owner's app syncs; a Clip visitor may see slightly stale data, and feedback appears for other members only after the owner's device next syncs. Acceptable for v1; document it.
4. **Server-to-server key custody.** The CloudKit web-services private key must live only outside `public_html`, never in the repo or the Clip binary.
5. **Unshipped Space feature.** Everything here rides on a feature that has never been through two-device or production-schema testing; treat H2/H4 as real gates, not formalities.
6. **Photo attachments in the Clip.** Mirroring image assets to the public DB adds cost/size; v1 can mirror thumbnails only or omit images.
7. **cPanel process/CPU limits.** CloudLinux-based shared hosts cap resources per account — fine for a small user base, but the write endpoint isn't built to survive a traffic spike.

**Total estimate:** ~11–16 working days of Clip work (excluding the Space H2–H5 stabilization), compressible by descoping the write path (saves ~2.5–3.5 days).

### Critical files for implementation
- `Reflect/Services/Space/SpaceCloudService.swift` — sync hooks for mirror publishing and pending-feedback ingestion
- `Reflect/Services/Space/SpaceCloudServiceProtocol.swift` — protocol additions for mirror/ingest
- `Reflect/App/DIContainer.swift` — pattern to mirror in `ClipDIContainer`; new mirror-service wiring
- `Reflect/Presentation/Features/Space/Share/CloudSharingView.swift` — replace raw CKShare URL with wrapper invite link
- `Reflect/App/SpaceInviteInbox.swift` — full-app universal-link/token resolution into the existing accept flow

### Sources
[What's new in App Clips — WWDC22](https://developer.apple.com/videos/play/wwdc2022/10097/) · [Apple Developer Forums: App Clips and CloudKit public database](https://developer.apple.com/forums/thread/658307) · [What's new in CloudKit — WWDC21](https://developer.apple.com/videos/play/wwdc2021/10086/)
