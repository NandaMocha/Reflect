# H2 Runbook — Two-Device Spike

> **Purpose:** prove the CloudKit share accept round-trip works between two real devices on two
> different iCloud accounts. H2 is the P0 exit criterion and the single gate blocking H3, H4, H5,
> and all three App Clip phases. Everything else in the Space feature is code-complete.

Status: **not yet run.** Written 2026-08-05. Companion: [space-progress.md](space-progress.md).

## Why this can't be skipped or simulated

The share accept path (`CKAcceptSharesOperation` + `hierarchicalRootRecordID`) needs a *second
iCloud account* accepting a share created by the first. Simulators can't sign into a second iCloud
account reliably, and one account sharing with itself does not exercise the participant lane —
which is precisely where the risk lives. Two findings already depend on real-device confirmation:

- **R4-F1:** `isMine` is fail-closed on the shared lane because `__defaultOwner__` there means the
  *share owner*, not the current participant. The semantics need proving on hardware.
- Incremental zone sync (T26–T29): "second fetch of a quiet zone transfers ~nothing" is unverified.

## Before you start

| # | Prerequisite | Notes |
|---|---|---|
| 1 | **Device A** — iPhone 16, iCloud account #1 | Already has the build; `devicectl` id `6920DFDC-D656-5ABD-9AA5-A9BB73DBF989` |
| 2 | **Device B** — any iOS 17+ device, iCloud account #2 | The blocker. Must be a *different* Apple ID, signed into iCloud, with iCloud Drive on |
| 3 | Both devices on network, iCloud signed in | Settings ▸ [name] ▸ iCloud — confirm before building |
| 4 | Device B registered for development signing | See "Signing Device B" below — do this first; it is the usual source of delay |
| 5 | A way to send a link between accounts | Messages/Mail between the two Apple IDs, or AirDrop |

### Signing Device B

Device B must be in the provisioning profile or the install fails. Plug it in, then:

```bash
xcrun devicectl list devices          # copy Device B's identifier
```

Build with `-allowProvisioningUpdates` and Xcode registers it automatically, provided the Apple ID
has Team `9NAU7R3577` access. If it refuses, add the UDID manually in the developer portal under
Devices, then rebuild.

### Build and install (both devices)

```bash
DD=/tmp/dd-h2      # out-of-tree DerivedData: avoids sim/device build clashes

xcodebuild -project Reflect.xcodeproj -scheme Reflect \
  -destination 'platform=iOS,name=<DEVICE NAME>' \
  -configuration Debug -allowProvisioningUpdates -derivedDataPath "$DD" build

xcrun devicectl device install app --device <DEVICE ID> \
  "$DD/Build/Products/Debug-iphoneos/Reflect.app"
```

Both devices must run **the same build**. A mismatched pair produces confusing results that look
like sync bugs.

The harness is at **Settings ▸ 🧪 Space Debug (spike)** (`SettingsView.swift:86`), DEBUG builds only.

---

## The run

Work top to bottom. Every button named below exists in `SpaceDebugView`; the **Log** section at the
bottom of that screen records each result — screenshot it if anything fails.

### Phase 1 — Device A creates and shares

| Step | Action (Device A) | Expect |
|---|---|---|
| A1 | **Check availability** | Account available. If not, iCloud isn't signed in or the container is unreachable — stop and fix |
| A2 | **Create test space** | Succeeds; "Selected space" section appears showing zone + lane **private** |
| A3 | **Share invite** | Share sheet appears with a CKShare URL |
| A4 | Send the link to Device B's Apple ID (Messages/Mail) | Link arrives on B |

**If A3 fails**, suspect T4's atomic root+share — the root record and `CKShare` are saved in one
`CKModifyRecordsOperation`, and a partial failure there surfaces here.

### Phase 2 — Device B accepts

> **Expected noise, not a failure:** with the Space Debug screen *open* on Device B, an invite is
> accepted twice — once by `SpaceInviteInbox` routing and once by the debug view's own
> `.spaceShareInviteReceived` observer (R3 finding #7, left in place deliberately as the spike
> harness). A duplicate/"already accepted" error in the log here is expected. To avoid it entirely,
> have the app **closed** on B when you tap the link.

| Step | Action (Device B) | Expect |
|---|---|---|
| B1 | Tap the link with the app **closed** | App launches and accepts; no black screen (cold-launch path, `scene(_:willConnectTo:)`) |
| B2 | **List joined spaces** | The space from A2 is listed, lane **shared** |
| B3 | **Write probe reflection** | Succeeds |
| B4 | Force-quit, enable **airplane mode**, reopen | Space and reflection still render from the SwiftData cache |

**If B1 fails**, suspect the accept wiring in T1/T2 — `CKSharingSupported` in Info.plist, or the
`AppDelegate`/`SceneDelegate` accept entry points.

### Phase 3 — Device A sees B's write

| Step | Action (Device A) | Expect |
|---|---|---|
| A5 | **Dump zone records** | B's probe reflection appears |
| A6 | **Dump zone records** again immediately | Second fetch of a quiet zone transfers ~nothing (T26 incremental sync) |

### Phase 4 — Photo attachment

Added to H2 because photo assets ride the same zone-fetch path and have never been verified across
devices.

| Step | Action | Expect |
|---|---|---|
| P1 | On A, create a feedback request **with a photo** through the real UI (not the debug screen) | Saves |
| P2 | On B, refresh | Row thumbnail **and** thread-header image both render |
| P3 | On B, force-quit → airplane mode → reopen | Image still renders from cache |

### Phase 5 — Authorship (R4-F1)

| Step | Action | Expect |
|---|---|---|
| F1 | On B, view A's request | **No delete affordance** on A's content |
| F2 | On B, view B's own answer | Delete affordance **is** present |

This is the fail-closed `isMine` check. If B can delete A's content, stop — that is a security
finding, not a polish item.

---

## Pass criteria

H2 is green when A1–A6, B1–B4, P1–P3 and F1–F2 all behave as described. Record the outcome as a
one-line note in `space-plan.md` §12 and update the H2 line in
[space-progress.md](space-progress.md).

## Do these in the same session

Getting Device B is the expensive part, so don't spend it on H2 alone. Once B is set up, continue
straight into:

- **H3** — two-device P1 UI verification: create → invite → join → leave → remove → delete through
  the real UI, plus the cold-launch invite.
- **TASK-014** (multi-answer) — only statically verified so far, and needs two accounts: post three
  answers to one question, edit the middle one, delete the first, confirm the other two are
  untouched on the second device; attach a photo to a second answer; switch segments; have the owner
  delete a question and confirm the cascade removes *all* of that question's answers, not one per
  member; check both exports increment `answerIndex` per member per question; kill and relaunch for
  cache-first paint.

## If it fails

| Symptom | Prime suspect |
|---|---|
| Share creation fails (A3) | T4 — atomic root + `CKShare` in one operation |
| Link does nothing / black screen (B1) | T1/T2 — `CKSharingSupported`, AppDelegate/SceneDelegate accept wiring |
| Accepted but space not listed (B2) | Lane routing — joined spaces read the **shared** DB |
| B's write invisible on A (A5) | Zone-change fetch, or parent references not carrying the share |
| B can delete A's content (F1) | R4-F1 `isMine` regression — **security, stop and fix** |
| Second fetch re-downloads everything (A6) | T26–T29 change tokens not persisting |

## After H2

H4 (Dev→Production schema) is the next release footgun, and its deploy list now includes both the
multi-question changes (`Answer`, `questionsJSON`) and the App Clip's `PendingClipFeedback` public
record type. See [app-clip-plan.md](app-clip-plan.md).
