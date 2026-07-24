# Auto-Sync Verification Guide

**Status**: In development (Tasks 1–5 implemented; Tasks 6–7 in progress).
**Last verified against code**: 2026-07-24

This document describes how to **manually verify** the auto-sync feature because there is no automated test target. Each check is run against the live CloudKit Dashboard and on-device behavior. Verification must pass before the feature can ship.

---

## Quick context

The auto-sync feature (Path B: Transactional Outbox) propagates every create/update/delete of a Reflection or Learning to the user's **private CloudKit database** in the background. The implementation uses:

- **Outbox model** (`PendingSyncOp`) to queue mutations
- **Deterministic record IDs** (keyed by UUID, not random recordNames) for idempotent upserts
- **Incremental push** with child reconciliation (unused attachments are purged server-side)
- **Background drain** on lifecycle events, network reconnect, and a `BGProcessingTask`

See [auto-sync-plan.md](auto-sync-plan.md) for the full design.

---

## Prerequisites

### CloudKit Dashboard Schema Setup

**The `reflectionID` and `learningID` fields on child record types MUST be marked as Queryable.** The app queries these to find orphaned attachment records (images, voice recordings, videos) when a reflection is synced or deleted, and to clear learningID when a learning is deleted.

**Steps:**

1. Open the [CloudKit Dashboard](https://dashboard.iCloud.com).
2. Select your Private Database for the Reflect app (under the correct team/container).
3. For each of these record types, select it and click **Metadata**:
   - `CKImageAttachment`
   - `CKVoiceRecording`
   - `CKVideoAttachment`
4. Under **Queryable Fields**, ensure both `reflectionID` and `learningID` (if present) have checkmarks.
   - If either is missing, click the field row, toggle **Queryable**, and save.
5. Wait for replication to the CloudKit edge (~10–30 seconds).

**Why:** The push operation queries `reflectionID` to find and delete orphaned children. If the field is not queryable, the query fails and the app skips reconciliation (degrades gracefully). You will see orphans left on the server until this is fixed.

---

## Verification Checklist

### 1. Enable Auto-Sync & Create a Reflection

- [ ] In Settings → Cloud Sync, toggle **Auto-sync** ON.
- [ ] Create a reflection with at least one image and one title.
- [ ] Allow 3–5 seconds for the sync coordinator to drain the outbox.
- [ ] In CloudKit Dashboard, navigate to **CKReflection** records and confirm **exactly one** record exists with `recordName == <your reflection UUID>` (visible in the app's reflection detail or via the model's `id` field).
- [ ] Verify that record has `localID == <reflection UUID>` and `title == <your title>`.

**Expected outcome:** One record, deterministic recordName, no duplicates.

---

### 2. Idempotency: Edit Twice Without Sync Drain

- [ ] Create another reflection.
- [ ] Open it for edit immediately (before sync drains).
- [ ] Change the title to "Edit 1".
- [ ] Tap Save, but do not wait for sync.
- [ ] Immediately edit again: change to "Edit 2".
- [ ] Tap Save and wait 5 seconds for drain.
- [ ] In CloudKit Dashboard, verify **exactly one** `CKReflection` record exists for this reflection (not two).
- [ ] Verify that record's `title == "Edit 2"`.

**Expected outcome:** Coalesced into a single server record; title shows the final value.

---

### 3. Attachment Orphan Cleanup

- [ ] Create a new reflection and add **two images** to it.
- [ ] Tap Save, wait 5 seconds for sync.
- [ ] In CloudKit Dashboard, find the `CKReflection` record and note its ID.
- [ ] Verify that **two** `CKImageAttachment` records exist with `reflectionID == <reflection ID>`.
- [ ] Back in the app, edit the reflection and **remove one image** (keep the other).
- [ ] Tap Save, wait 5 seconds for sync.
- [ ] In CloudKit Dashboard, refresh the CKImageAttachment records for that reflection.
- [ ] Verify that **only one** `CKImageAttachment` remains with `reflectionID == <reflection ID>`.

**Expected outcome:** Removed attachment record is purged from the server; the one kept remains.

---

### 4. Delete Tolerance: Unsync'd & Repeated Deletes

**Test 4a: Delete reflection that was never synced**
- [ ] Create a reflection but do not wait for sync (or disable Auto-sync first).
- [ ] Delete the reflection immediately from the app.
- [ ] Verify **no crash or error dialog** appears; the app remains responsive.

**Test 4b: Delete a reflection twice**
- [ ] Create a reflection, wait 5 seconds for sync.
- [ ] Delete it from the app, wait for sync drain.
- [ ] Verify the `CKReflection` record is gone from the Dashboard.
- [ ] Force-delete the record manually from the Dashboard (if it still exists).
- [ ] In the app, force-close and reopen (or trigger a manual retry of the sync operation if UI exists).
- [ ] Verify **no crash or hang**; the app tolerates the already-missing record gracefully.

**Expected outcome:** No crashes; app remains responsive and does not re-enqueue failed deletes indefinitely.

---

### 5. Learning Deletion: Clearing learningID on Reflections

- [ ] Create a **Learning** (e.g., "Python Basics").
- [ ] Create **two reflections** under that learning.
- [ ] Wait 5 seconds for sync; verify both `CKReflection` records exist with `learningID == <learning UUID>`.
- [ ] Delete the learning from the app.
- [ ] Wait 5 seconds for sync.
- [ ] In CloudKit Dashboard, verify that:
  - The `CKLearning` record is gone.
  - **Both** `CKReflection` records still exist (reflections do not cascade-delete).
  - **Both** reflection records now have `learningID == ""` (empty string, the unlinked sentinel).

**Expected outcome:** Learning is removed, reflections are re-upserted with cleared learningID.

---

### 6. First-Enable Re-Key Backup

*This test requires a device or account that already has old manual backups.*

**Scenario:** A user has been backing up manually (random recordNames on the server). They enable Auto-sync for the first time.

- [ ] On a test device, manually back up the current local store via Settings → "Back Up Now" (old full-replace path).
- [ ] Verify that random-named `CKReflection` and `CKLearning` records exist in CloudKit Dashboard (recordNames are UUIDs or random strings; note a few).
- [ ] Disable Auto-sync (toggle OFF in Settings).
- [ ] Force-close and reopen the app.
- [ ] Enable Auto-sync (toggle ON).
- [ ] The app should:
  - Pause the sync coordinator.
  - Run a one-time full `backup()` (same as "Back Up Now" but writing deterministic recordNames).
  - Resume the sync coordinator.
  - Complete without dialog (or show a brief progress overlay).
- [ ] Wait 10 seconds for the full backup to drain.
- [ ] In CloudKit Dashboard, verify that:
  - **Old random-named records are still present** (the re-key creates new deterministic ones; old ones are left for manual cleanup in a future release).
  - **New deterministic records exist** (recordName == UUID), one per entity.
  - **Total count per entity type** is exactly the number of local learnings and reflections (no dupes across old and new).

**Expected outcome:** A fresh set of deterministic-ID records is created; old records coexist (future cleanup task).

---

### 7. Lifecycle & Background: Offline Drain & Reconnect

**Test 7a: Offline enqueue → online drain**

- [ ] Disable iCloud or toggle Airplane Mode ON.
- [ ] Create a reflection (or edit one).
- [ ] Verify in the app that the sync state shows "Offline" or "Syncing…" (pending).
- [ ] In the Data layer, check that a `PendingSyncOp` row was created (inspect the local SwiftData store via Xcode's SwiftData inspector or Debug Console).
- [ ] Toggle Airplane Mode OFF or reconnect to iCloud.
- [ ] Wait 3–5 seconds.
- [ ] Verify in CloudKit Dashboard that the reflection now appears (synced).
- [ ] Verify that the `PendingSyncOp` row is gone from the local store.

**Expected outcome:** Ops queued offline are drained on reconnect without user intervention.

**Test 7b: Background → Foreground flush**

- [ ] Create a reflection and verify it's queued (PendingSyncOp exists, not yet drained).
- [ ] Return to the home screen (background the app).
- [ ] Wait 2–3 seconds, then return to the app (foreground).
- [ ] Verify that the reflection is now synced to CloudKit Dashboard.

**Expected outcome:** Foreground transition triggers a drain.

**Test 7c: BGProcessingTask simulation (advanced)**

*This test simulates the background processing task that runs even when the app is not in the foreground.*

- [ ] Create a reflection and note that it's queued.
- [ ] Background the app (press Home or slide up).
- [ ] Open Xcode Console (or use `lldb`) and run:
  ```lldb
  e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"xyz.nandamochammad.Reflect.sync-drain"]
  ```
- [ ] Wait 5–10 seconds.
- [ ] Open the app or check CloudKit Dashboard to verify the queued operation was drained.

**Expected outcome:** BGProcessingTask fires and drains pending ops even while backgrounded.

---

### 8. Conflict Policy & Last-Push-Wins

- [ ] Create a reflection on **Device A** and wait for sync.
- [ ] Edit the same reflection on **Device B** (using the same iCloud account) and change a field (e.g., title).
- [ ] Wait 3–5 seconds for Device B to sync.
- [ ] Edit on **Device A** again (bumping a different field, e.g., body) and sync.
- [ ] Pull all entities on Device B (`restore()` or manual refresh).
- [ ] Verify that Device B's local state reflects Device A's most recent edits.

**Expected outcome:** Last-push-wins per field; no merge conflict UI appears. (This is acceptable for a single-user journal. Multi-user requires a more sophisticated merge strategy in a future release.)

---

## Failure modes & troubleshooting

| Symptom | Likely cause | Check |
|---|---|---|
| Orphaned attachment records remain after editing | `reflectionID` field is not queryable on CKImageAttachment / CKVoiceRecording / CKVideoAttachment | See Prerequisites section; ensure Queryable is enabled |
| Duplicate CKReflection records appear with the same UUID | Deterministic ID generation is broken or conflicting with old random-named records | Verify recordName == UUID; if old random-named records exist, run first-enable re-key (Test 6) |
| PendingSyncOp rows pile up and never drain | `checkCloudAvailability()` is returning `.unavailable` or backoff is stuck | Check network connectivity; verify iCloud account is signed in; inspect logs for backoff state |
| Delete returns an error or causes a crash | `pushDeletes` does not tolerate missing records | Verify the delete operation catches and ignores `.unknownItem` CKError |
| learningID is not cleared when a learning is deleted | Affected reflections are not re-enqueued | Verify `LearningRepository.delete()` enqueues upserts for each affected reflection |

---

## Running the checks

**In order:**

1. **Prerequisites:** Set CloudKit Dashboard queryable fields.
2. **Checks 1–5:** Can run on a fresh device; test core push + idempotency + orphan cleanup + delete tolerance + learning delete.
3. **Check 6:** Requires a device with prior backups; can be deferred to the next manual test pass.
4. **Check 7:** Can run on a fresh device; test offline resilience and background behavior.
5. **Check 8:** Requires two devices on the same iCloud account; can be deferred.

**Sign-off:** Once all checks pass, the feature is ready for QA / beta testing.
