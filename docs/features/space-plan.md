# Space — Collaborative Groups (Implementation Plan)

> **Status: PLAN — not implemented.** This document is the design/decision record for a major
> new collaborative feature. Nothing in the codebase implements Space yet.

## Decisions (locked 2026-07-18)

The gating decisions have been made — the plan follows the recommended path:

1. **Backend:** **Supabase (Postgres + row-level security)**. Both hard requirements
   (join-by-ID approval, hidden-until-reveal) are enforced **server-side** via RLS.
2. **Identity:** **Sign in with Apple**, required **only when entering the Space feature**.
   The rest of the app stays account-free. → commits us to **in-app account deletion**
   (App Store requirement).
3. **Reveal model:** a reflection's **creator can read responses before revealing**. "Reveal"
   just flips visibility for the *other* members — **no client-side encryption needed**.

These are settled; the phased plan below is the path forward.

---

## 1. Requirements (as stated by the user)

Quoted verbatim so the plan stays honest to the ask:

> - A **Space** is a group people can join.
> - Members can create **Reflections inside a Space**.
> - Other members can **join a reflection and add their own responses**.
> - Other members **cannot see anyone else's responses until the reflection's creator opens/reveals them**.
> - A member **only sees the Spaces they have joined**.
> - **Join flow:** a person enters a **Space ID**, sends a **join request**; the space **creator approves or declines**.

Two of these are *hard* requirements that shape the whole architecture:

- **(HR-1) Join-by-ID with approval** — a stranger types a Space ID, a request goes to the
  creator, and the creator approves or declines. This is a *request/queue* model, not an
  *invite-link* model.
- **(HR-2) Hidden-until-reveal responses** — member B must be genuinely unable to read member
  C's response until the creator reveals. "The app doesn't show it" is not the same as "the
  server won't return it." This needs **per-record, server-side access control**.

---

## 2. Where the app is today (why this is a big deal)

Reflect is **local-first and single-user**:

- SwiftData persistence, `cloudKitDatabase: .none` in `Reflect/ReflectApp.swift` — CloudKit
  automatic sync is deliberately off.
- Sync is a **manual backup** via a custom `CloudSyncService`
  (`Reflect/Services/Cloud/CloudSyncService.swift`) writing `CKRecord`s to the user's
  **private** database. Restore is currently a placeholder.
- **No user accounts, no sign-in.** The CloudKit container
  (`iCloud.xyz.nandamochammad.Reflect`, see `Reflect/Reflect.entitlements`) holds only the
  user's own data.
- The `Reflection` model (`Reflect/Data/Models/Reflection.swift`) is a personal journal entry:
  rich text + images/voice/video, tied to a local `Learning`.

**"Other people joining" is a fundamentally new capability.** Every prior feature could be
built device-side; Space cannot. It needs (a) a shared backend, (b) a notion of identity, and
(c) server-enforced permissions. That also drags in App Store obligations the app has never
had: user-generated-content moderation (App Review Guideline 1.2: report/block/EULA) and
in-app account deletion (Guideline 5.1.1(v)) if we add sign-in.

---

## 3. Identity — who is a "person"?

| Option | How it works | Pros | Cons |
|---|---|---|---|
| **CloudKit user identity** (`fetchUserRecordID`) | Every iCloud account gets a stable, per-container opaque ID. No UI. | Zero sign-up friction; matches app's no-account ethos | Only works with a CloudKit backend; user discovery APIs are deprecated (iOS 17+); no identity off-Apple; can't be verified by a non-Apple server |
| **Sign in with Apple (SIWA)** | One-tap Apple auth issuing a verifiable token + stable `sub` per team | Verifiable by *any* backend; privacy-friendly (email relay); familiar; required anyway if we ever add other logins | Introduces an account concept → Apple requires in-app account deletion; small onboarding step |
| **Custom accounts** (email/password) | Classic sign-up | Full control | Highest friction, password handling liability, no upside for this app |

**Recommendation: Sign in with Apple**, gated *only* on the Space feature (the rest of the
app stays account-free). It is the only option that works with every backend candidate,
produces a token a server can verify (which HR-1/HR-2 enforcement depends on), and is
one tap. Users never touch Space → never see a sign-in screen.

Each user gets a **Profile** (self-chosen display name, optional emoji/avatar) created on
first Space use — no discovery of real names/emails, ever.

---

## 4. Backend — evaluation and recommendation

### Option A — CloudKit public database + custom membership/permission records

- **How:** `Space`, `Membership`, `JoinRequest`, `SpaceReflection`, `Response` as record
  types in the **public** database; identity = CloudKit user record ID.
- **HR-1 (join by ID + approval):** *mechanically* possible — requester writes a
  `JoinRequest` record; creator queries and flips status.
- **HR-2 (hidden until reveal): fails.** CloudKit public-DB security is **Security Roles**
  (World / Authenticated / Creator) applied **per record type**, not per record. If
  "Authenticated" can read `Response` records at all, *any* signed-in iCloud user — not even
  just space members — can query everyone's responses with a plain CKQuery. Hiding would be
  client-side theater. The only real fix is client-side end-to-end encryption (responders
  encrypt to the creator's public key; creator re-publishes on reveal) — a significant
  cryptographic subsystem with key distribution, rotation, and multi-device problems.
- Also: no server-side validation at write time (anyone can insert a `Membership` record
  claiming to be a member — every read has to distrust the data), no rate limiting, no
  moderation hooks.
- **Verdict:** free and serverless, but cannot honestly enforce HR-2 and only weakly
  enforces HR-1. Rejected as primary.

### Option B — CloudKit sharing (CKShare / shared database / custom zones)

- **How:** each Space is a custom zone in the creator's private DB, shared via `CKShare`;
  participants see it in their shared database.
- **HR-1: model mismatch.** CKShare is **invite-out** (owner sends a share URL / adds
  participants), the requirement is **request-in** (stranger enters an ID, owner approves).
  There is no "request to join" primitive. Worse, adding a participant programmatically
  requires `CKUserIdentity` lookup by email/phone — the discovery APIs for this are
  deprecated since iOS 17. You'd end up bolting a public-DB request queue onto CKShare
  and still hitting the participant-lookup wall.
- **HR-2: fails.** Share participants have zone-level access; every participant can read
  every record in the shared zone. Per-record hiding inside a share does not exist.
- **Verdict:** the *worst* fit despite being the "native sharing" API. Rejected.

### Option C — Custom backend (Supabase / Firebase / bespoke API) — **RECOMMENDED: Supabase**

- **How:** Postgres + **Row-Level Security (RLS)** + Supabase Auth (native SIWA support) +
  official `supabase-swift` SDK. Firebase (Firestore + security rules) is equivalent in
  capability; a bespoke API server is strictly more work.
- **HR-1: enforced.** `join_requests` is a table; RLS lets a requester insert exactly one
  pending request for a space they can name, lets only the space owner read/resolve
  requests, and a trigger/RPC creates the `membership` row on approval. The client cannot
  self-insert a membership — the database refuses.
- **HR-2: enforced.** A single RLS policy on `responses` — readable iff *you wrote it*, or
  *you created the parent reflection*, or *the reflection is revealed (and you're a
  member)*. A malicious client, curl, or a modified app binary gets zero rows. This is real
  access control, not client-side hiding.
- **Trade-offs (honest):** a second backend beside CloudKit; data leaves the Apple
  ecosystem (privacy-policy + App Privacy label updates, region choice for GDPR);
  free tier is fine for launch but it's a paid dependency at scale; requires SIWA
  (Option A wouldn't); you now own schema migrations on a server.
- Why Supabase over Firebase: SQL + RLS expresses HR-2 in ~10 lines and is auditable;
  relational fits this model (memberships, uniqueness constraints, joins); no vendor
  query-language lock-in; Firestore rules can do it too but are harder to reason about
  and Firestore's pricing model punishes the fan-out reads this feature does.

### Decision matrix

| | HR-1 join-by-ID + approval | HR-2 hidden until reveal | Server-side validation | Ops cost | New user friction |
|---|---|---|---|---|---|
| A. CloudKit public DB | ⚠️ client-enforced only | ❌ (needs client E2E crypto) | ❌ | none | none |
| B. CKShare | ❌ invite-link model, deprecated lookup | ❌ zone-level access | ❌ | none | none |
| **C. Supabase (rec.)** | ✅ RLS + RPC | ✅ RLS | ✅ | low (managed) | SIWA, one tap |

**Recommendation: Option C (Supabase + Sign in with Apple).** It is the only option where
both hard requirements are enforced *by the server*. If the user is unwilling to take a
non-Apple dependency, the fallback is Option A **plus client-side encryption for HR-2 and
acceptance that HR-1 is only client-enforced** — materially more code and weaker guarantees;
this plan assumes Option C.

---

## 5. Data model

Server-side (Postgres) is the source of truth. On-device, Space data is a **read-through
cache** in its own SwiftData store (`SpaceStore`, modeled on `Shared/Insight/InsightStore.swift`
— separate container, separate schema, never touching the main store).

```
profiles
  user_id      uuid PK            -- = auth.uid() from SIWA
  display_name text (1..30)
  avatar_emoji text?
  created_at   timestamptz

spaces
  id           uuid PK
  join_code    text UNIQUE        -- 8-char human-typable "Space ID", e.g. "R7KQ-2MXF"
  name         text (1..50)
  detail       text?
  creator_id   uuid → profiles
  created_at   timestamptz

memberships                        -- "a member only sees spaces they joined"
  space_id     uuid → spaces      \  PK (space_id, user_id)
  user_id      uuid → profiles    /
  role         enum: owner | member
  joined_at    timestamptz

join_requests
  id           uuid PK
  space_id     uuid → spaces
  requester_id uuid → profiles
  status       enum: pending | approved | declined
  message      text? (0..200)     -- optional "hi, it's Nanda"
  created_at   timestamptz
  resolved_at  timestamptz?
  resolved_by  uuid?              -- the owner who acted
  UNIQUE (space_id, requester_id) WHERE status = 'pending'   -- no request spam

space_reflections                  -- NEW type; NOT the local Reflection model
  id                 uuid PK
  space_id           uuid → spaces
  author_id          uuid → profiles
  title              text (1..200)
  prompt_text        text          -- body/question members respond to (text-only in MVP)
  responses_revealed bool DEFAULT false      -- ← the reveal state
  revealed_at        timestamptz?
  created_at / updated_at

responses
  id                   uuid PK
  space_reflection_id  uuid → space_reflections
  author_id            uuid → profiles
  body                 text (1..5000)
  created_at / updated_at
  UNIQUE (space_reflection_id, author_id)    -- one response per member
```

Relationships: `Space 1—N Membership`, `Space 1—N JoinRequest`, `Space 1—N SpaceReflection`,
`SpaceReflection 1—N Response`. Reveal is **per reflection** (one switch reveals all its
responses), which matches the requirement; per-response reveal is a possible later refinement.

### Client-side Swift types

New domain entities (`Domain/Entities/Space/…`) mirroring the tables, plus SwiftData cache
models in a dedicated `SpaceStore` container. **`SpaceReflection` is a new type, not an
extension of `Reflection`** — see §7.

---

## 6. Permission & visibility enforcement (server vs client)

**Principle: the client is untrusted.** Everything below is RLS in Postgres; SwiftUI just
renders what the server is willing to return.

| Rule | Enforced server-side (RLS/RPC) | Client's role |
|---|---|---|
| Only members see a space & its content | `SELECT` on `spaces`/`space_reflections` requires a `memberships` row for `auth.uid()` | renders the list |
| Join-code lookup doesn't leak the space list | `spaces` not selectable by non-members; lookup goes through a `SECURITY DEFINER` RPC `request_to_join(join_code, message)` that returns only *name + creator display name* and inserts the pending request | join form UI |
| Only the owner sees/resolves join requests | `SELECT/UPDATE` on `join_requests` restricted to space owner (requester may `SELECT` own rows to show "pending…") | approval inbox UI |
| Membership can't be self-granted | no direct `INSERT` on `memberships`; only the `approve_request(request_id)` RPC (checks caller = owner) creates it | — |
| **Hidden until revealed (HR-2)** | `SELECT` on `responses`: `author_id = auth.uid() OR reflection.author_id = auth.uid() OR (reflection.responses_revealed AND caller is a member)` | shows "N responses waiting" placeholder |
| Only the creator reveals | `UPDATE … SET responses_revealed` allowed only when `author_id = auth.uid()` (via RPC `reveal_responses(reflection_id)`) | reveal button |
| One response per member | DB `UNIQUE (space_reflection_id, author_id)` | disables the compose button |
| Members respond, non-members don't | `INSERT` on `responses` requires membership in the parent space | — |

**Why client-only hiding is insufficient:** any member's auth token can hit the REST/realtime
API directly (curl, a jailbroken device, a modified build). If the server returns unrevealed
response rows and the *app* filters them, the "surprise reveal" guarantee is fiction — one
member could read everyone's answers early and, socially, that breaks the whole feature
(think retro/ice-breaker use). RLS makes the unrevealed rows non-existent to everyone but
their author and the reflection's creator.

Whether the reflection *creator* may read responses before revealing is a product choice —
the policy above allows it (simplest, and the creator "opens" them anyway). Flag if the user
wants the creator blind too; that would push toward the encryption design.

---

## 7. Coexistence with the existing app (additive, zero-touch)

- **The local `Reflection`/`Learning`/`Insight` features do not change.** No schema change
  to the main `ModelContainer`, no change to `InsightStore`, no change to existing use cases.
- **`SpaceReflection` is a new type**, not an extension of `Reflection`. Reasons: the local
  `Reflection` is rich-text + media + `Learning`-bound + badge-coupled
  (`CreateReflectionUseCase` triggers `EvaluateBadgesUseCase`); a space reflection is
  text-first, server-owned, has an author and reveal state, and must never be swept up by
  the personal iCloud backup in `CloudSyncService`. Extending `Reflection` with nullable
  `spaceID/authorID/revealed` fields would poison every existing fetch, the backup path, and
  badge evaluation. Bridging later ("copy my response into my journal") is a one-way
  *export*, not a shared model.
- **Isolation pattern already exists in this repo:** `InsightStore` (separate ModelContainer,
  separate schema, non-fatal fallback). `SpaceStore` copies that pattern for the offline
  cache.
- **Wiring follows house conventions:** new `Data/Repositories/Protocols/Space*Protocol.swift`
  + implementations backed by a `SpaceAPIClient` (Supabase) instead of SwiftData;
  `Domain/UseCases/Space/` one-class-per-action (`CreateSpaceUseCase`,
  `RequestToJoinSpaceUseCase`, `ApproveJoinRequestUseCase`, `RevealResponsesUseCase`, …);
  `DIContainer` gains `makeSpace…()` factories; UI lands in
  `Presentation/Features/Space/{List,Detail,Join,Requests}` as a new tab or a section on the
  main tab. Badges/achievements ignore Space entirely in MVP.
- If Space is ever removed, deleting the `Space*` folders and the tab leaves the app exactly
  as it is today.

## 8. Key flows

All mutations go through use cases → repository → Supabase RPC/table ops. Push notifications
(APNs via Supabase Edge Function or DB webhook) are Phase 3; before that, pull-to-refresh.

1. **Create space:** user signs in with Apple (first time only) → names the space → server
   inserts `spaces` (+ generates unique `join_code`) + owner `membership` in one RPC → UI
   shows the code with a Share/Copy button ("Share this Space ID").
2. **Request to join:** joiner taps "Join a Space" → signs in if needed → enters the code →
   `request_to_join` RPC returns space name for a confirm screen and creates the pending
   request → joiner sees "Pending approval".
3. **Approve / decline:** creator's "Requests" inbox lists pending requests (display name +
   message) → Approve calls `approve_request` (creates membership, marks resolved) → Decline
   marks declined. Requester's next refresh shows the space (or a declined state). A declined
   user may request again (rate-limited, see §9 below and abuse notes).
4. **Create a reflection in a space:** any member → title + prompt text → inserted with
   `responses_revealed = false` → appears to all members.
5. **Add a response:** member opens the reflection → composes → insert (unique per member) →
   others see "3 responses · hidden until <creator> reveals", never the bodies.
6. **Reveal:** the reflection's creator taps "Reveal responses" (confirmation alert —
   irreversible in MVP) → `reveal_responses` RPC sets the flag → everyone's next
   fetch/realtime event returns the bodies.
7. **Leave / remove:** member leaves (deletes own membership; their revealed responses
   remain, attributed); owner removes a member (RPC; removed user loses all access via RLS
   instantly). Owner deletes the space → cascade. Owner leaving requires transfer-or-delete
   (MVP: owners can't leave, only delete).

## 9. Security, privacy, abuse

**What leaves the device (new — must be disclosed in privacy policy + App Privacy labels):**
SIWA identifier, chosen display name, space names, reflection titles/prompts, response text,
timestamps. MVP is deliberately **text-only** — no images/voice/video in spaces — which keeps
the upload surface and moderation burden small. Personal journal data (`Reflection`,
`Learning`, `Insight`) never touches the new backend.

**Who can read what:** enforced by RLS per §6. Supabase service keys never ship in the app
(only the anon key + user JWT); TLS in transit; encryption at rest per Supabase. Choose the
project region deliberately (user is in Indonesia; Singapore region is the sensible default).

**Abuse / spam on join requests:**
- Join codes are 8 chars from a 32-symbol alphabet (~1.1 × 10¹²) — not enumerable; lookup
  only via the RPC, which is rate-limited (e.g. 10 lookups/hour/user) so codes can't be
  brute-forced.
- One pending request per (space, user); declined users can retry after a cooldown, max N
  total; owner can regenerate the join code (invalidates the old one) if it leaks.
- Owner can remove members; removed/declined users can be blocked from re-requesting.
- **App Review Guideline 1.2 (UGC):** must ship report-content + block-user + EULA/terms
  before release, and **5.1.1(v)**: in-app account deletion (delete profile, memberships,
  authored content or anonymize). These are non-negotiable App Store requirements, not
  nice-to-haves.

## 10. Phased delivery

Rough sizing assumes one developer; this is a **large** feature — realistically 8–12 weeks
to a shippable v1 across Phases 0–3.

**Phase 0 — Decisions & foundation (≈1–1.5 wk)**
- T0.1 Sign-off on Open Decisions (§11); create Supabase project (region: Singapore)
- T0.2 Schema + RLS policies + RPCs (`request_to_join`, `approve_request`, `reveal_responses`) as versioned SQL migrations
- T0.3 Add SIWA capability; add `supabase-swift` via SPM; `AuthService` (sign in, session, sign out) + `SpaceAPIClient`
- T0.4 RLS verification script (two test users; assert HR-1/HR-2 from raw REST, not the app)

**Phase 1 — MVP: spaces & membership (≈2–3 wk)**
- T1.1 Profile creation (display name) on first Space use
- T1.2 Create space + join-code display/share; spaces list (only joined ones)
- T1.3 Join flow: enter code → confirm → pending state
- T1.4 Owner request inbox: approve/decline
- T1.5 `SpaceStore` offline read cache + pull-to-refresh
- T1.6 DIContainer wiring, use cases, Space tab entry point

**Phase 2 — Reflections, responses, reveal (≈2–3 wk)**
- T2.1 Create/list space reflections
- T2.2 Compose response; "hidden" placeholder states ("N responses waiting")
- T2.3 Reveal flow + revealed reading UI
- T2.4 Leave space / remove member / delete space
- T2.5 Empty/error/loading states per house component library

**Phase 3 — Ship-blockers & polish (≈2–3 wk)**
- T3.1 Report content + block user + terms (Guideline 1.2)
- T3.2 In-app account deletion (Guideline 5.1.1(v))
- T3.3 Push notifications: join request received, approved, new reflection, responses revealed
- T3.4 Supabase Realtime for live updates (else stay on refresh)
- T3.5 Privacy policy + App Privacy labels update; TestFlight beta

**Later / explicitly out of MVP:** media in space reflections, per-response reveal,
multiple owners/moderators, response comments/reactions, exporting a response into the
personal journal, web read-only view.

## 11. Open decisions for the user

1. **Backend (biggest fork in the road).** Recommendation: **Supabase (Option C)**. The
   alternative — staying pure-Apple with CloudKit public DB — means HR-1 is only
   client-enforced and HR-2 requires a client-side encryption subsystem; CKShare doesn't fit
   at all. Accepting Supabase means: a non-Apple data processor, a privacy-policy update, and
   a small ops footprint. **Nothing can be scheduled until this is decided.**
2. **Identity.** Recommendation: **Sign in with Apple, required only for Space**. Alternative
   (anonymous CloudKit ID) only exists inside Option A and gives no verifiable identity for a
   server. Accepting SIWA commits us to in-app account deletion (T3.2).
3. **May the reflection's creator read responses *before* revealing?** Recommendation:
   **yes** (simplest; the creator controls the reveal anyway, and RLS grants them read). If
   the answer is *no — creator must be blind until reveal too*, that pushes toward client-side
   encryption and materially grows the design.
4. **MVP content scope.** Recommendation: **text-only** space reflections/responses (no
   photos/voice/video in v1) — keeps storage, bandwidth, and moderation obligations small and
   ships months earlier. Media becomes a Phase-4 candidate.

---

*Grounding references:* `Reflect/ReflectApp.swift` (store config, `cloudKitDatabase: .none`),
`Reflect/Services/Cloud/CloudSyncService.swift` (manual private-DB backup),
`Reflect/App/DIContainer.swift` (wiring pattern), `Shared/Insight/InsightStore.swift`
(isolated-store precedent), `Reflect/Data/Models/Reflection.swift` (why SpaceReflection is a
new type), `docs/architecture.md` (layering and conventions).
