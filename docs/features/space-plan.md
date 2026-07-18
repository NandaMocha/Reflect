# Space — Collaborative Groups via CloudKit Sharing (Implementation Plan)

> **Status: PLAN — not implemented.** This is the design/decision record for the Space
> feature. Nothing in the codebase implements Space yet.

## Locked decisions (2026-07-18)

These are settled — do not re-litigate:

1. **Backend: CloudKit only.** A Space **is a `CKShare`** — a shared record hierarchy in a
   custom zone. No third-party backend, no server, no ops footprint.
2. **Identity: the user's iCloud account.** Participant identity comes from
   `CKShare.Participant` / `CKUserIdentity`. **No Sign in with Apple, no custom accounts,
   no account-deletion system.**
3. **Join flow: share-link only.** The creator taps Share and sends an invite link via
   Messages / Mail / AirDrop / copy; tapping the link joins the space.
   **Dropped:** typed Space-ID codes, join-request queue, approve/decline.
4. **Visibility: all members see all content** — every reflection and every response in a
   space is visible to every member. **Dropped:** hidden-until-reveal, per-record permissions.
5. **Platform: Apple-only is acceptable.** Members must have an iCloud account and the app.

### Decision history — why the pivot from Supabase

The previous revision of this document recommended **Supabase + Sign in with Apple**, and
that was the right call *for the previous requirements*: join-by-typed-ID with an
approve/decline queue, and responses hidden until the creator revealed them. Both demanded
server-side, per-record access control that CloudKit cannot express — CKShare is invite-out
(not request-in) and grants zone-level visibility to all participants.

The user has since **scoped the feature down**: invite links instead of a join-request
queue, and full visibility instead of hidden-until-reveal. Those two cuts remove exactly
the requirements CloudKit couldn't meet. **CKShare's native model — owner invites via link,
participants see everything in the shared zone — is now precisely the feature.** With that,
a third-party backend, SIWA, account deletion, RLS policies, and a second data processor
all disappear. The Supabase evaluation is preserved in git history
(`docs/features/space-plan.md` prior to this rewrite) should the dropped requirements ever
return.

---

## 1. Requirements (current scope)

- A **Space** is a group people can join **via an invite link** sent by the creator.
- Members can create **reflections inside a Space** (text-first in MVP).
- Members can **add responses** to any reflection in the space.
- Everyone in the space sees everything in the space, live-ish (push-driven updates).
- A member only sees the spaces they own or have joined; members can **leave**; the
  creator can **remove a participant** or **delete the space**.

## 2. Where the app is today

- **Local-first, single-user.** SwiftData with `cloudKitDatabase: .none` and
  `groupContainer: .none` (`Reflect/ReflectApp.swift`) — automatic CloudKit sync is
  deliberately off.
- **Manual backup** via `CloudSyncService` (`Reflect/Services/Cloud/CloudSyncService.swift`):
  hand-rolled `CKRecord` mapping (`CKLearning`, `CKReflection`, `CKImageAttachment`,
  `CKVoiceRecording`) saved to the **private database** of `CKContainer.default()`.
  Restore is a placeholder.
- **Entitlements already in place** (`Reflect/Reflect.entitlements`): iCloud container
  `iCloud.xyz.nandamochammad.Reflect`, CloudKit service, `aps-environment` (development),
  App Group. Missing for Space: the `remote-notification` background mode and the
  `CKSharingSupported` Info.plist key (§8).
- **Isolation precedent:** `Shared/Insight/InsightStore.swift` — a separate ModelContainer
  with its own schema and a non-fatal tiered fallback, never touching the main store.
- Wiring via `DIContainer.shared` factories (`Reflect/App/DIContainer.swift`).

The good news vs. the Supabase plan: the container, entitlement, and CKRecord-mapping
skills this feature needs **already exist in the codebase**.

---

## 3. CloudKit architecture

### The shape

```
Owner's PRIVATE database                     Member's SHARED database
┌──────────────────────────────┐             ┌──────────────────────────────┐
│ Custom zone: Space-<UUID>    │   CKShare   │ (mirror of the owner's zone) │
│  ┌ Space (root CKRecord) ◄───┼── link ─────┼──► visible to participants   │
│  │  └ SpaceReflection        │             │     with .readWrite access   │
│  │     └ Response            │             │                              │
│  └ CKShare (zone-wide share) │             │                              │
└──────────────────────────────┘             └──────────────────────────────┘
```

- **One Space = one custom `CKRecordZone`** (e.g. `Space-<UUID>`) in the **creator's
  private database**, containing a root `Space` record, its child `SpaceReflection`
  records, and their child `Response` records.
- The zone is shared with a **`CKShare`**. Recommendation: share the **root record
  hierarchy** (`CKShare(rootRecord:)`) with every child setting `record.parent` to its
  parent record — parent references make children travel with the share automatically.
  (A zone-wide share, `CKShare(recordZoneID:)`, is the alternative; hierarchy sharing is
  chosen because one zone hosts exactly one space either way, and hierarchy shares are the
  path `UICloudSharingController`/`ShareLink` are built around.)
- `share.publicPermission = .none` (invite-only link) and participants are added with
  **`.readWrite`** permission so members can create reflections and responses.
- **Two databases per user:**
  - **Private DB** — zones for spaces *I created*. I am the owner.
  - **Shared DB** — mirrored zones for spaces *I joined* (zone appears after accepting
    the share; zone ID carries the owner's name).
  - "My spaces" = enumerate my private-DB space zones; "joined spaces" = enumerate
    shared-DB zones. Same record types, two databases — all reads/writes go through a
    small abstraction that knows which DB a given space lives in.
- Members create child records **in the shared database** inside the mirrored zone,
  setting `parent` appropriately; CloudKit propagates them to the owner and all other
  participants.

### Who wrote what

Every `CKRecord` carries system metadata: `creatorUserRecordID` and `lastModifiedUserRecordID`.
Display names come from matching `creatorUserRecordID` against
`CKShare.participants[*].userIdentity` (`nameComponents`). No profile system needed.
(Names can be nil if a participant hides them — fall back to "A member".)

---

## 4. Local persistence — decision

### Options weighed

| | A. Raw CloudKit (`CKRecord` + small local cache) | B. Core Data `NSPersistentCloudKitContainer` + sharing |
|---|---|---|
| Sharing API maturity | Full manual control (`CKShare`, `CKFetchRecordZoneChangesOperation` / `CKSyncEngine`) | Mature: `share(_:to:)`, `persistUpdatedShare`, `fetchShares(matching:)` |
| Fit with existing app | Matches the **existing manual-CKRecord competence** in `CloudSyncService` | Introduces a **Core Data stack** into a SwiftData app — two persistence frameworks |
| SwiftData? | Cache can be a plain isolated SwiftData store (no CloudKit coupling) | **SwiftData has no CKShare/sharing API** as of iOS 17/18 — B forces Core Data, not SwiftData |
| Complexity owned | Sync bookkeeping: change tokens, subscriptions, conflict handling (small: 3 record types, text-only) | Mirroring is a black box; sharing edge cases (share metadata stores, `.sharedPersistentStore` juggling) are notoriously fiddly |
| Isolation from main store | Trivial — mirrors `InsightStore` | Possible but heavier (separate `NSPersistentContainer` + two store descriptions private/shared) |

### Recommendation: **A — raw CloudKit with a thin, isolated local cache**

Reasons, in order:

1. **SwiftData cannot do CKShare.** Option B is really "adopt Core Data for this feature."
   That's a second persistence framework and the `NSPersistentCloudKitContainer` mirroring
   black box, permanently, for a feature with **three text-only record types**.
2. The app **already does manual CKRecord mapping** (`CloudSyncService`) — Option A is more
   of the same pattern, not a new discipline.
3. Space data is **server-authoritative and small**. The local layer is a *cache for
   offline reading + fast launch*, not a system of record. A dedicated `SpaceStore`
   (separate SwiftData ModelContainer, modeled exactly on `InsightStore`: own schema,
   `cloudKitDatabase: .none`, non-fatal fallback) — or even a first-cut in-memory cache —
   is sufficient.
4. **Sync plumbing:** prefer **`CKSyncEngine`** (iOS 17+, matches the deployment target) —
   it owns change tokens, batching, retries, and account changes for both the private and
   shared databases, and works with shares. Fallback if it fights us:
   `CKFetchRecordZoneChangesOperation` + manually stored change tokens (the classic path).

**Explicitly untouched:** the main ModelContainer (`Learning`, `Reflection`, attachments,
badges), `InsightStore`, and `CloudSyncService`'s backup flow. Space adds a new store and
a new service; it modifies none of the existing persistence.

---

## 5. Data model

All CloudKit record types live in the space's custom zone. Timestamps use CloudKit's
system `creationDate`/`modificationDate` where possible (one less field to maintain).

```
Space (root record, 1 per zone)
  name          String (1..50)
  detail        String?          -- optional description
  emoji         String?          -- optional icon
  [system] creatorUserRecordID   -- the owner
  [system] creationDate

SpaceReflection (parent → Space)
  title         String (1..200)
  promptText    String           -- the body/question members respond to (text-only MVP)
  [system] creatorUserRecordID   -- author = any member
  [system] creationDate / modificationDate

Response (parent → SpaceReflection)
  body          String (1..5000)
  [system] creatorUserRecordID   -- author
  [system] creationDate / modificationDate
```

- `record.parent` is set on every child so the share hierarchy carries them.
- **Authorship/display** resolved via `CKShare.participants` (§3). No Profile record type.
- **No uniqueness constraint** is enforceable server-side in CloudKit, so "one response per
  member" (from the old plan) is dropped: **multiple responses per member are allowed**,
  comment-thread style. (If one-per-member matters, it's client-side-only enforcement —
  flag as product choice, see §11.)
- Client-side Swift domain entities in `Domain/Entities/Space/` (`Space`,
  `SpaceReflection`, `SpaceResponse` — value types mapped from CKRecords), plus cache
  `@Model` classes in the isolated `SpaceStore`.

**`SpaceReflection` is a new type, NOT the local `Reflection`** (§7): the local model is
rich-text + media + `Learning`-bound + badge-coupled and is swept by the personal backup;
a space reflection is text-first, share-owned, multi-author. Reusing `Reflection` would
poison existing fetches, `CloudSyncService.backup`, and badge evaluation.

---

## 6. Key flows

All mutations go through use cases → repository → `SpaceCloudService` (house conventions:
`Domain/UseCases/Space/`, one class per action; `DIContainer` gains `makeSpace…()`
factories; UI in `Presentation/Features/Space/{List,Detail,Compose}`).

1. **Create space** — user names it → create custom zone in private DB → save `Space` root
   record + `CKShare(rootRecord:)` **in one `CKModifyRecordsOperation`** (CloudKit requires
   the share and root saved atomically) with `publicPermission = .none`.
2. **Invite** — present the share sheet to get the link out:
   `UICloudSharingController` (wrapped in `UIViewControllerRepresentable`) or SwiftUI
   `ShareLink` with `CKShareTransferRepresentation`. Recommendation: start with
   `UICloudSharingController` — it also gives the owner the participant-management and
   stop-sharing UI for free. Owner sends via Messages/Mail/AirDrop/copy.
3. **Accept an invite** — ⚠️ **real integration point in the app target.** Tapping the
   link routes to the app; acceptance arrives via the scene delegate:
   `windowScene(_:userDidAcceptCloudKitShareWith:)` handing us `CKShare.Metadata` →
   `CKAcceptSharesOperation`. Reflect is a pure SwiftUI-lifecycle app with **no
   app/scene delegate today** — we must add `@UIApplicationDelegateAdaptor` + a
   `UIWindowSceneDelegate` (via `application(_:configurationForConnecting:)`), plus the
   **`CKSharingSupported = YES`** Info.plist key so the OS offers the app for share links.
   After acceptance, the zone appears in the user's **shared DB**; navigate straight into
   the joined space.
4. **List spaces** — "My spaces": fetch space zones/roots from private DB. "Joined":
   `fetchAllRecordZones` on the shared DB → fetch each zone's root `Space` record. Merge
   into one list with an owner/member marker; back it with the `SpaceStore` cache.
5. **Create a reflection** — member composes title + prompt → save `SpaceReflection` with
   `parent = space root` into the correct DB (private if owner, shared if member).
6. **Add a response** — open reflection → compose → save `Response` with
   `parent = reflection`. Others see it on next push/fetch.
7. **Leave a space** (participant) — remove self: delete own participant via
   `CKShare` (a participant can remove themselves; simplest UI path is
   `UICloudSharingController`'s built-in option, or delete the zone from *my shared DB*,
   which removes my participation — it does **not** delete the owner's data).
8. **Remove a participant / stop sharing** (owner) — edit `share.participants` and re-save
   the share (or `UICloudSharingController`'s management UI). Removed member loses access
   on their next sync.
9. **Delete a space** (owner) — delete the custom zone from the private DB
   (`CKModifyRecordZonesOperation`): destroys the share and all content for everyone.
   Confirmation alert; irreversible.

## 7. Coexistence & isolation

- **Additive, zero-touch.** No schema change to the main ModelContainer, no change to
  `InsightStore`, no change to existing use cases or the backup path. Deleting the
  `Space*` folders and the tab entry point returns the app to exactly today's state.
- **Same container, different lanes.** `CloudSyncService` (backup) writes
  `CKLearning`/`CKReflection`/… records to the private DB's default zone. Space uses
  **custom zones** (private DB) and the **shared DB** with distinct record types
  (`Space`, `SpaceReflection`, `Response`). No record-type or zone overlap;
  `deleteAllCloudData()` touches only the backup's four record types. No conflict.
  - Housekeeping note: `CloudSyncService` uses `CKContainer.default()`; the Space service
    should reference `CKContainer(identifier: "iCloud.xyz.nandamochammad.Reflect")`
    explicitly (they resolve to the same container today, but explicit is safer).
- **Badges/achievements ignore Space** in MVP (no badge triggers from space activity).
- Bridging ("copy a space reflection into my journal") is a later one-way export, not a
  shared model.

## 8. Entitlements, capabilities, config

Already present: iCloud container `iCloud.xyz.nandamochammad.Reflect`, CloudKit service,
`aps-environment` (APNs), App Group.

To add:
- **Info.plist `CKSharingSupported = YES`** (app advertises it accepts share links).
- **Background Modes → Remote notifications** (`UIBackgroundModes: remote-notification`)
  so CloudKit subscription pushes wake the app for silent sync.
- Register for remote notifications at launch (`registerForRemoteNotifications` — no user
  permission prompt needed for silent pushes; user-visible pushes are optional later).
- **CloudKit Console:** define the three record types + indexes in the **Development**
  environment, then **deploy schema to Production** before TestFlight/App Store —
  a classic release-blocking footgun if forgotten.
- No Developer-portal additions beyond what the existing iCloud + push entitlements
  already require (APNs is implicit with the aps-environment entitlement).

## 9. Sync & realtime

- **Subscriptions:** one **`CKDatabaseSubscription`** on the **shared database** and one on
  the **private database** (covering owned space zones), each with silent-push
  (`shouldSendContentAvailable`) notification info. Database subscriptions are the
  recommended pattern for custom zones and are what `CKSyncEngine` sets up for you if we
  adopt it — another point for `CKSyncEngine`.
- **On push (or foregrounding):** fetch changed zones → fetch zone changes with stored
  change tokens → upsert into `SpaceStore` cache → UI (Observation) updates.
- **Do not trust push for delivery.** Silent pushes are throttled/coalesced by iOS.
  Always also sync on: app foreground, space screen appear, and pull-to-refresh.
  Push makes it feel live; fetch makes it correct.
- **Conflicts:** text-append workload (new child records) rarely conflicts. For edits to
  existing records, handle `serverRecordChanged` with last-writer-wins on whole fields —
  sufficient for MVP.
- **Coexistence with `CloudSyncService`:** the backup remains a user-triggered, one-shot
  private-DB operation on different record types in the default zone. The Space sync loop
  never touches those records and vice versa (§7).

## 10. App Store / safety (UGC — lighter, but not zero)

No accounts means no Guideline 5.1.1(v) account-deletion obligation — that whole
workstream from the Supabase plan is gone. But content shared between users is still
**user-generated content**, and Guideline 1.2 typically expects:

- **Report objectionable content** — MVP-acceptable: a "Report" action on
  reflections/responses that pre-fills an email to the developer (no server needed),
  plus the ability for the owner to delete any record in their zone (owners have full
  control of their zone's records).
- **Block / escape** — "Leave space" (participant) and "Remove participant" (owner)
  already cover the escape hatch; call them out in the App Review notes.
- **Terms/EULA** acknowledging no tolerance for objectionable content — a one-time sheet
  before first Space use.

Budget a small task for this (P2); it is a ship consideration, not an architecture driver.

## 11. CloudKit gotchas (accepted, with mitigations)

1. **Share-acceptance UX is fragile-feeling:** if the recipient lacks the app, the link
   lands on a generic iCloud web page (no store redirect for non-public apps in dev).
   Test the full link → install → accept path via TestFlight before judging it.
2. **`.readWrite` is zone-hierarchy-wide:** any participant can technically modify or
   delete *another member's* records via raw API (CloudKit has no per-record ACL inside a
   share). The UI will only offer edit/delete on your own records — but this is
   client-enforced. Accepted: consistent with "all members see/do everything" scope and a
   trusted-small-group product.
3. **Participant leaving vs. owner deleting differ:** a participant removing the zone from
   their shared DB only removes *their access*; the owner deleting the zone destroys the
   space *for everyone*. Get the copy in confirm dialogs right.
4. **Eventual consistency / latency:** seconds (occasionally more) between a write and
   other devices seeing it; silent pushes can be delayed or dropped. Design the UI for
   "recently synced", not "realtime chat".
5. **Testing needs two real iCloud accounts on real devices.** Simulators can't reliably
   receive CloudKit pushes, and share acceptance flows are limited there. Plan for two
   physical devices (or device + second account on a Mac) from P0 — this is the #1
   schedule risk.
6. **Schema deploy to Production** (§8) before any external build.
7. **Account edge cases:** no iCloud account signed in, iCloud restricted, account
   switching mid-session (`CKAccountChanged` — `CKSyncEngine` surfaces this). MVP: Space
   tab shows a "Sign in to iCloud in Settings" empty state (reuse
   `CloudSyncService.checkCloudAvailability` semantics).
8. **Rate limits & record sizes:** irrelevant at this text-only scale, but keep responses
   ≤ ~1 MB per record (CloudKit hard limit) — the 5000-char cap handles it.

## 12. Phased delivery

**This is roughly half the previous plan** (was 8–12 weeks): no backend project, no auth,
no RLS, no account deletion, no join-request system, no reveal machinery.
**Revised estimate: ~4–6 weeks to a shippable v1** (one developer), dominated by
CloudKit-sharing integration verification rather than code volume.

**P0 — CloudKit sharing spike & plumbing (≈1 wk)** — *de-risk first, UI later*
- T0.1 Entitlements/Info.plist: `CKSharingSupported`, remote-notification background mode;
  register for remote notifications; add `UIApplicationDelegateAdaptor` + scene delegate
  with `userDidAcceptCloudKitShareWith`.
- T0.2 Spike, two devices / two iCloud accounts: create zone + root record + CKShare,
  send link, accept, fetch from shared DB, write a child record back, see it on device A.
  **Exit criterion: round trip proven end-to-end.** (This spike retires the majority of
  the feature's risk.)
- T0.3 Define record types in CloudKit Console (Development); decide `CKSyncEngine` vs
  manual operations based on spike experience.

**P1 — Create / join / list spaces (≈1.5–2 wk)**
- T1.1 `SpaceCloudService` (zone/share/CRUD ops) + repository protocol + implementations;
  `SpaceStore` isolated cache (InsightStore pattern); DIContainer factories.
- T1.2 Create-space flow + `UICloudSharingController` invite sheet.
- T1.3 Accept-invite routing → land in the joined space.
- T1.4 Spaces list (owned + joined merged), leave space, owner delete space,
  owner manage/remove participants (sharing controller UI).
- T1.5 iCloud-unavailable / empty / error states.

**P2 — Reflections, responses, push (≈1.5–2 wk)**
- T2.1 Create/list `SpaceReflection` in a space (both DB lanes).
- T2.2 Compose/list `Response` with author names from share participants.
- T2.3 Database subscriptions + silent push → sync → cache → UI; foreground/pull-to-refresh
  fallback sync.
- T2.4 UGC ship items: report action, first-use terms sheet, App Review notes (§10).
- T2.5 Deploy schema to Production; TestFlight beta with ≥2 external testers exercising
  the invite path.

**Later / out of MVP:** media in space reflections, reactions/comments on responses,
export a space reflection into the personal journal, user-visible push notifications
("Nanda responded…"), per-member response limits.

## 13. Residual open questions & risks (for the user)

1. **Multiple responses per member?** CloudKit can't enforce one-per-member server-side.
   Recommendation: allow multiple (comment-style). If you want one-per-member, it's
   client-enforced only — say so and we'll add it to the composer logic.
2. **Trust model inside a space.** Any participant *technically* can edit/delete others'
   records (gotcha #2). Fine for friends/study groups; if Space is ever aimed at
   strangers, this becomes a real limitation (CloudKit has no fix — that would reopen the
   backend question). Confirm the intended audience is trusted small groups.
3. **Invite-link UX for non-users.** Link → App Store → install → tap link again is only
   smooth once the app is public; during TestFlight it's clunky. Accept for beta?
4. **`CKSyncEngine` vs manual operations** — decided empirically in the P0 spike; no
   user input needed unless the spike forces a deployment-target or complexity trade-off.
5. **Two-device testing logistics** — needs a second physical device + second iCloud
   account throughout development (schedule risk #1).

---

*Grounding references:* `Reflect/ReflectApp.swift` (store config: `cloudKitDatabase: .none`,
`groupContainer: .none`), `Reflect/Services/Cloud/CloudSyncService.swift` (manual private-DB
backup, default-zone record types), `Reflect/Reflect.entitlements` (iCloud container
`iCloud.xyz.nandamochammad.Reflect`, CloudKit, aps-environment),
`Reflect/App/DIContainer.swift` (wiring pattern), `Shared/Insight/InsightStore.swift`
(isolated-store precedent), `Reflect/Data/Models/Reflection.swift` +
`Reflect/Data/Models/Learning.swift` (why `SpaceReflection` is a new type),
`docs/architecture.md` (layering and conventions). Superseded Supabase plan: this file's
prior revision in git history.
