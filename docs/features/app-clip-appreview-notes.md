# App Review notes — Reflect Clip (App Store Connect submission)

Ticket **AC-051**. This document is written to be pasted directly into App Store Connect's
**App Review Information → Notes** field for the Reflect Clip App Clip submission, with three
sections (UGC mechanisms, demo instructions, privacy delta) that can also be lifted individually
into the relevant App Store Connect screens. The data-flow section is background for the
reviewer/developer, not reviewer-facing copy.

Background: [app-clip-plan.md](app-clip-plan.md) "Decision 1" (2026-08-05 revision) and its
linked tickets AC-010–AC-015, AC-020/AC-021, AC-030. This doc describes what actually shipped in
those tickets, not aspirational design.

---

## 1. UGC 1.2 compliance — the four mechanisms

Reflect Clip lets an invited guest post text answers ("feedback") into someone else's private
Space without creating an account. Because guests can post user-generated content, Apple's
Guideline 1.2 (User-Generated Content) applies. Reflect Clip's UGC posture relies on the Space
being a small, invite-only, trusted group — not an open public feed — combined with four concrete
mechanisms:

### (a) Report affordance

Each guest answer has a **Report** action, implemented separately in the two targets that render
it:

- In the full app, `ReportContentButton`
  (`Reflect/Presentation/Features/Space/Compliance/ReportContentButton.swift`) appears on the
  request (`Reflect/Presentation/Features/Space/Detail/SpaceDetailView.swift:116`) and on each
  guest answer in `AnswerBubble`/thread views.
- In the guest Clip, `ClipAnswerBubble`
  (`ReflectClip/Features/AllFeedback/ClipAnswerBubble.swift`, ~line 167) reimplements the same
  mailto affordance Clip-side (it cannot import `ReportContentButton`, which lives outside
  anything shared into `ReflectClip` — see `Reflect/ClipShared/README.md`), rather than reusing
  the full-app component. Report is offered **only for mirror-confirmed answers** in the Clip: a
  guest's own just-submitted, not-yet-confirmed draft has no server-side record yet, so there's
  nothing for the owner to look up if reported, and the Clip has no report action on the request
  itself.

Both implementations open the device's Mail composer pre-addressed to the developer
(`nanda.mocha@gmail.com`), pre-filled with the content kind, the CloudKit `recordName` of the
reported content, and the Space name (the request's title in the Clip's case, since the Clip never
fetches the Space name), so a report is immediately actionable without any extra lookup. The user
still has to tap Send — this only stages the report — which keeps the affordance usable offline
and avoids a bespoke reporting backend.

### (b) Owner delete of guest answers

Guest answers are created **as CloudKit records owned by the Space owner's device** — ingestion
(AC-012, see §4 below) runs on the owner's app, which is the only client that can write into the
owner's private/shared zone. That means every guest `Answer` already has
`creatorUserRecordID == owner`, so CloudKit's native permission model lets the owner delete it
with no new authorization machinery. `Thread/AnswerBubble.swift` renders a delete affordance on a
guest-authored bubble specifically when the current user is the Space **owner** (`isSpaceOwner`,
wired through `SpaceThreadView`/`SpaceAllResponsesView`); the delete use case's ownership guard is
`isMine || (isGuest && isSpaceOwner)` — extended, not bypassed, from the existing own-content-only
guard. This is a genuine remove-objectionable-content mechanism: the owner of the Space can take
down any guest post at any time from within the full app.

### (c) Token revocation as a block mechanism

Every guest feedback link is a random, unguessable 128-bit token (`ClipToken.generate()`,
`Reflect/ClipShared/ClipMirrorSchema.swift`, base64url, not a UUID; minted by
`SpaceCloudService.ensureRequestToken` per request). Deleting the request (or the whole Space)
revokes that token: `SpaceMirrorService.revokeMirror(for:)` deletes the public `TokenIndex` record
plus every mirrored record published under that token, and the PHP write endpoint's token lookup
(`clip-feedback.php`, `tok-<token>` record) then 404s on any further submission attempt.
Revocation (`SpaceCloudService.revokeMirrorsIfOwned`) is wired into the two deletion paths that
end a request's life — deleting the reflection/request and deleting the whole Space (which is
also this app's only complete share-revocation mechanism today: destroying the zone destroys its
`CKShare` along with every participant's access). There is **no separate stop-sharing-only-this-
Space entry point** in `SpaceCloudService` — the system `UICloudSharingController`'s own "Stop
Sharing" action bypasses this service entirely, so a share stopped that way does not revoke the
guest-feedback token or the public mirror (see AC-014; a real gap, not a mitigated case). In
practice, fully revoking access to a Space means deleting it, which does trigger revocation. This
is the "block an abusive participant" story for the deletion paths that do run it: since access is
per-link rather than per-account, revoking the link is equivalent to blocking whoever holds it —
existing guest content is unaffected (mechanism (b) handles takedown of what's already posted;
revocation only stops *new* submissions).

### (d) Invite-only, unguessable links

There is no discovery surface, directory, or public feed anywhere in the Clip. The only way to
reach a feedback request is via the link the owner explicitly shares (Messages/Mail/AirDrop/etc.,
outside the app), which encodes the 128-bit token above. A guest cannot browse to another Space's
feedback, cannot enumerate tokens, and cannot see anything published under a different request.
Combined with (a)–(c), this is a closed, invite-only-audience posture rather than an open UGC
platform, which is the basis for treating report + owner-delete + revocation as sufficient under
1.2 without a pre-publication moderation/approval queue (see Decision 1 in app-clip-plan.md for
the full reasoning, including why an approval queue was deliberately not built for v1).

---

## 2. Demo instructions for App Review

Reflect Clip has no login. To see the guest-feedback flow end to end, reviewers need a working
feedback link (the App Clip invocation URL) that points at a live, seeded feedback request.

**Demo link/token:** `[PLACEHOLDER: demo token]`

> This placeholder is intentionally left unfilled — minting and seeding a real demo token is
> ticket **AC-H5**, a human-gated follow-up (requires deploying against the Production CloudKit
> environment and manually creating a seeded request). Before submitting to App Store Connect,
> replace the placeholder above with the actual `https://nandamochammad.xyz/f/<token>` (or
> equivalent App Clip invocation URL) and re-verify the steps below against it.

Suggested reviewer-facing steps once the placeholder is filled in:

1. Tap the demo link above (or scan the associated App Clip code / paste the URL into Safari).
   Reflect Clip launches without requiring an install of the full Reflect app.
2. The Clip shows a seeded feedback request with one or more prompts.
3. On first launch the Clip asks for a display name (no account, no email, no password) — enter
   any name.
4. Type a short answer to a prompt and submit.
5. The submission is queued and sent to a small write endpoint that stages it for the request
   owner; there is no visible confirmation that a *specific person* received it beyond the
   in-Clip "sent" state, since the Clip cannot read back into the owner's private data. This is
   expected — the Clip is intentionally write-only into the owner's Space (see §4, data flow).
6. Optional: from the feedback list, use the "Report…" action on any **already-confirmed** guest
   answer (not on your own just-submitted pending answer, and not on the request itself — the
   Clip only offers Report on mirror-confirmed answers) to see mechanism (a) above (opens a
   pre-filled Mail draft; no need to actually send it).

No test account or credentials are required — the Clip only requires the demo link/token above.

---

## 3. Privacy nutrition-label delta

What Reflect Clip's data collection looks like relative to Apple's privacy nutrition label
categories, for App Store Connect's App Privacy questionnaire:

| Data type | Collected by the Clip? | Purpose | Linked to identity? | Tracking? |
|---|---|---|---|---|
| **Display name** | Yes | App functionality (attributing the guest's answer in the owner's Space) | Yes, to the guest's submission (not to any account — there is no account) | No |
| **User-generated content** (the guest's typed answers) | Yes | App functionality (the core feature — delivering feedback to the request owner) | Yes, to the guest's submission | No |
| **Contact info, identifiers (email/phone/device ID/IDFA), location, usage/analytics data, diagnostics** | No | — | — | No |

Key points for the App Store Connect questionnaire:

- **Data collected**: display name and user-generated content only. Both are entered directly by
  the guest at submission time; neither is collected passively.
- **No tracking**: the Clip does not use IDFA, does not link data across apps or websites owned
  by other companies, and does not use the data for advertising. Answer **"No"** to "Do you use
  data for tracking purposes?"
- **No account, no persistent identity**: there is no login. `guestId` is a locally-generated,
  per-device identifier used only to attribute a guest's own answers to them within one Space (so
  e.g. they don't see someone else's answer as "your answers" on re-open); it is not a
  cross-Space or cross-app identity and is not exposed to other guests.
- **Storage**: guest submissions transit a small PHP write endpoint (server-to-server signed
  request, no data retained by that endpoint beyond a short-lived rate-limit counter keyed by IP
  and token — see `scripts/server/clip-feedback.php`) and land in Apple CloudKit, in a public
  staging record type (`PendingClipFeedback`) that has no world-read access — the owner reads it
  as an authenticated user — until the owner's app ingests it and deletes the staging copy (§4).
- **Data deletion**: because guest answers become CloudKit records owned by the request owner
  (see §1(b)), the owner deleting the answer, the request, or the Space deletes the guest's data
  once it has been ingested into a real `Answer` record. Revoking a request's link (§1(c)) stops
  the link from resolving and removes the public mirror records (`TokenIndex`,
  `MirroredRequest`/`MirroredAnswer`) for that token, but it does **not** retroactively delete any
  `PendingClipFeedback` records already staged for that token but not yet ingested —
  `SpaceMirrorService.revokeMirror(for:)` only touches the mirror record types, and the only code
  path that deletes a `PendingClipFeedback` record is a successful ingest
  (`SpaceClipIngestService.deletePendingRecord`). In practice, revocation happens as part of
  deleting the owning request or Space, so the reflection those pending records would have been
  ingested against is also gone — the staged submissions become orphaned and unreachable (there
  is no live tokenized request left for the owner's app to ingest them against) rather than
  actively deleted. They are not otherwise cleaned up today.

This is a **delta** against the full Reflect app's existing privacy label — it describes only
what the *Clip target* collects, since the Clip and the full app are declared separately in App
Store Connect. It does not change the full app's existing label.

---

## 4. Data-flow diagram (prose)

There is no client-to-client connection between the guest's Clip and the owner's device — the
guest's device and the owner's device never talk directly. Data moves through two intermediate,
short-lived staging points instead:

1. **Guest's Clip → PHP endpoint.** The guest types an answer in Reflect Clip and submits. The
   Clip cannot write to CloudKit directly (App Clips don't get a CloudKit container of their
   own), so it POSTs the answer (plus the request's link token, a locally-generated `guestId`, and
   the guest's display name) to a small PHP endpoint hosted on existing cPanel hosting
   (`scripts/server/clip-feedback.php`). The endpoint validates the token, validates the
   question ID against the request's known questions, checks length limits and per-IP/per-token
   rate limits, then signs and calls Apple's CloudKit Web Services on the guest's behalf using a
   server-to-server key — it holds no long-lived guest data itself beyond a rolling rate-limit
   counter.

2. **PHP endpoint → `PendingClipFeedback`.** The endpoint writes one `PendingClipFeedback` record
   per answer into CloudKit's **public** database, under a deterministic record name
   (`"pcf-" + submissionId`) so a retried submission overwrites in place instead of duplicating.
   This record type has no world-read access — the owner reads it as an authenticated user (by
   the request's link token). It is a staging area, not a durable store — nothing is meant to
   live here long-term.

3. **`PendingClipFeedback` → owner app ingest.** The next time the Space owner's full Reflect app
   runs its normal CloudKit sync, `SpaceClipIngestService`
   (`Reflect/Services/Space/SpaceClipIngestService.swift`, ticket AC-012) queries
   `PendingClipFeedback` for every one of the owner's own tokenized requests, re-validates each
   pending answer independently (never trusting the endpoint's validation alone — length caps,
   question ID must belong to the request's current question set, well-formed record name), then
   writes it as a real `Answer` record into the owner's private/shared Space zone with guest
   attribution (`guestId`/`guestName` fields, so the full app can render a "guest" byline instead
   of misattributing it as the owner's own answer). Only after the `Answer` save succeeds does it
   delete the `PendingClipFeedback` record — save-then-delete, in that order, so a crash between
   the two steps leaves the pending record in place and a retry lands on the same deterministic
   `Answer` record name (idempotent, not duplicated).

One documented latency trade-off: a guest answer ingested during a sync pass isn't visible in the
**public mirror** (the read-only `MirroredRequest`/`MirroredAnswer` records other guests' Clips
read from) until the *next* sync pass republishes it, since that pass's mirror data was fetched
before ingestion ran. This is a known, accepted trade-off (see `SpaceClipIngestService.swift`
header comment and app-clip-plan.md "Guest round trip"), not a bug.
