# Space — Incremental Retrieval Plan (per-zone change tokens)

Status: **PLANNED — not started.** Written 2026-07-29, right after photo attachments landed on
feedback requests (`imageAsset` on `SpaceReflection`, commit `b05ed20`).

## Why now

Every Space refresh (`fetchReflections` / `fetchResponses`) runs `fetchAllRecords` —
a `CKFetchRecordZoneChangesOperation` with a **nil change token**, i.e. a full-zone download,
every time (`SpaceCloudService.swift:177`). Database-level tokens exist (`syncChanges`,
T22) but they only detect *that* a zone changed; the follow-up record fetch still pulls
everything.

That was fine for text-only records. With photos, a full-zone fetch may re-transfer **every
attached asset on every refresh** (CloudKit's daemon-level asset cache is undocumented
best-effort — design as if it misses). A space with 30 requests averaging ~100 KB of image
each costs ~3 MB per pull-to-refresh, per member. Compression caps the bleeding; incremental
fetch stops it.

## Goal / non-goals

**Goal:** a member's refresh transfers only records that actually changed since their last
fetch — unchanged requests (and their assets) are not re-downloaded at all.

**Non-goals:**
- On-demand asset loading (`desiredKeys` splitting, thumbnails-first). Not needed once
  unchanged records stop arriving; revisit only if single-fetch payloads get heavy.
- Any change to the write path, record schema, or the push/subscription layer (T22 stays).
- Personal-journal backup (`CloudSyncService`) — untouched, per the isolation constraints.

## Design

### Current shape (what changes)

```
refresh → fetchAllRecords(zone, token: nil)     → ALL records, ALL assets
        → filter by type, map, resolve authors
        → reconcile: upsert fetched + DELETE cached rows absent from fetch (grace window)
```

### Target shape

```
refresh → fetchZoneChanges(zone, token: saved)  → changed records + deleted recordIDs + new token
        → apply delta: upsert changed, delete by ID (cascade responses)
        → token expired? clear token, fall back to today's full fetch + set-difference reconcile
```

Two load-bearing consequences:

1. **Reconcile semantics flip.** Today "absent from fetch" means stale → delete (with a grace
   window). Under incremental fetch, absence means *unchanged* — deletion is only ever
   explicit (`recordWithIDWasDeletedBlock`). The set-difference reconcile must run **only**
   on full fetches (nil/expired token). Getting this wrong silently wipes healthy cache rows
   — it is the main risk of the whole plan.
2. **Deltas arrive mixed.** One zone delta can contain reflections, responses, and member
   profiles together. The repository applies the whole delta in one pass instead of the
   current per-screen scoped fetches. Screens keep their existing read paths (cache-first);
   only the refresh plumbing changes.

Token storage: per-zone `CKServerChangeToken`, archived to UserDefaults keyed
`spaceZoneToken-<zoneName>-<ownerName>` — same pattern as the DB tokens (T22), cleared on
`changeTokenExpired`, zone delete/purge, and leave/delete of the space.

## Task breakdown

| Ticket | Layer | Work | Acceptance |
|---|---|---|---|
| **T26** | Service | `fetchZoneChanges(in:database:)` on `SpaceCloudService`: per-zone token load/save/clear helpers; returns `(changed: [CKRecord], deletedIDs: [CKRecord.ID], fullFetch: Bool)`; `fullFetch=true` when token was nil/expired (then internally identical to today's `fetchAllRecords`). `withRetry` + `changeTokenExpired` → clear token, retry once as full. Protocol + mock updated. | Build green; harness (T29) shows second fetch of an unchanged zone returns 0 records. |
| **T27** | Repository | `applyZoneDelta` in `SpaceRepository`: upsert changed reflections/responses (reuse existing upserts incl. `imageData`), explicit deletes by recordID with response cascade; set-difference reconcile (+ grace window) runs **only when `fullFetch`**. `fetchReflections`/`fetchResponses` route through it; authorship/`isMine` resolution unchanged. | Full-fetch path behaves byte-identically to today (regression guard); incremental path never deletes a row without an explicit deleted ID. |
| **T28** | Repository | Cache-preservation guard: an upsert must never null a cached `imageData` when the incoming record carries no asset but `modifiedAt` is unchanged (protects against partial/failed asset staging on an otherwise-unchanged record). | Unit-level check via harness: kill staging file mid-cycle → cached photo survives next refresh. |
| **T29** | Debug + docs | `SpaceDebugView`: show per-zone token presence, "clear zone tokens" button, last-fetch counters (changed/deleted/full?). Update `space-progress.md` tables + fold verification into H2/H3 device checklists (see below). | Counters visibly drop to 0-record deltas on quiet zones during H2/H3 runs. |

Sequencing: T26 → T27 (T28 folds into T27's PR if small) → T29. Each ticket ends build-green
per the standing `xcodebuild` gate, one commit each.

## When

**After H2 passes, before H5/TestFlight.** Rationale: H2 validates the *current* fetch path
on real hardware first (photo delivery included) — optimizing an unverified path risks
debugging two layers at once. The change is member-invisible (same data, less transfer), so
it slots cleanly between the hardware gates. It must not block H2.

## Risks

| Risk | Mitigation |
|---|---|
| Incremental path deletes rows it shouldn't (semantics flip, risk #1 above) | `fullFetch` flag gates the set-difference reconcile; T27 acceptance explicitly tests "absent ≠ deleted". |
| Token drift after leave/delete/re-join of a space | Clear zone tokens in the same code paths that clear caches (leave, delete, zone-purged). |
| Stale `authorDisplayName` for unchanged records (profiles change but records don't) | Member profiles arrive in the same delta; re-resolve names for cached rows when a `MemberProfile` record is in the delta. |
| `changeTokenExpired` mid-operation | Already-handled pattern from T22: clear + full refetch; T26 reuses it. |

## Ship-gate amendments (photo attachments, applies regardless of this plan)

- **H2/H3 (two-device):** add — *member device receives a photo-carrying request; thumbnail
  renders in the space list row and header image in the thread; airplane-mode reopen still
  renders it (SwiftData cache, not CloudKit staging).*
- **H4 (schema deploy):** the `SpaceReflection` record type now includes the **`imageAsset`**
  field — it must exist in the Dev schema being deployed to Production (auto-created on
  first dev-build photo post; verify in CloudKit Console before deploy).
