# Multiple Answers per Question + Thread UI Revision — Implementation Plan

Status: **Planned, not started.** Written 2026-08-05, following [multi-question-feedback-plan.md](multi-question-feedback-plan.md) (complete). Verified against the live codebase 2026-08-05: all struct/method/file references below were read, not recalled. UI sketch: <https://claude.ai/code/artifact/12f27288-27d7-4de3-9f0e-613b5292fdcd>.

## Feature summary

Three revisions to the Space feedback flow:

1. **A member can post more than one answer to the same question.** Today `SpaceAnswer.recordName(reflectionID:questionId:authorRecordName:)` is deterministic, so a second answer computes the same CKRecord ID and silently overwrites the first. Answers become individually-identified records; edit and delete act on an answer id, not on a question.
2. **`SpaceThreadView` is restructured** — horizontal header (title/note left, 88pt square photo right, both text blocks clamped to 3 lines), and the tap-to-select question list is replaced by the same segmented control `SpaceAllResponsesView` already uses, with the selected question's answers stacked below it and an always-live composer.
3. **Export moves from `confirmationDialog` to `Menu`** in `SpaceAllResponsesView`.

Edit and remove behavior is otherwise unchanged.

## Clarified decisions

1. **Answers are chat-like** — appended in time order, each editable in place, composer stays pinned at the bottom. Not a form-like set revised as a whole.
2. **The answered-checkmark becomes a dot** on the segmented control. "Answered" is no longer binary, so a checkmark overstates it.
3. **No author grouping** in the all-answers list. Consecutive answers from one member stay separate bubbles with repeated bylines; timestamps carry the sequence.
4. **CSV keeps one row per answer**, with a new `answerIndex` column, rather than joining a member's answers into one cell.
5. **No migration.** CloudKit Space schema is still Dev-only (gate H4 in [space-progress.md](space-progress.md) remains open). Existing deterministically-named answer records stay readable — the record *name* changes shape, the schema does not — so a Dev reset is optional, not required.
6. **No CloudKit Console work.** No new record type and no new queried field, so the Queryable-`recordName`-index requirement does not apply here.

---

## Architectural overview

**Strategy: additive first, cutover once, delete last** — identical to the previous plan, and for the same reason: every task must leave `xcodebuild` green so the loop can consume them one at a time. New `createAnswer` / `updateAnswer` paths are introduced *alongside* `upsertAnswer` at every layer; `upsertAnswer` keeps compiling and keeps working until the view model cuts over in one atomic task, and is deleted in the final phase.

**What actually changes:** `SpaceAnswer.recordName` gains a UUID component, so identity moves from `(reflection, question, author)` to a genuine per-record id. Everything downstream follows from that. The SwiftData cache needs **zero** changes — `CachedAnswer.id` is already `@Attribute(.unique)` on the record name with no per-question uniqueness assumption, and `#Index` is on `reflectionID`.

**What does not change:** cloud-first mutation ordering, `SpaceZoneDelta` reconciliation, `CachedAnswer`, `DeleteOwnSpaceContentUseCase` (its `execute(answer:)` overload already takes a whole answer), `SpaceRecordMapper.makeAnswerRecord` (already parameterised by `recordName`), the compose sheet, the question editor, and the cascade-on-question-delete flow.

### New architectural surface

1. **Non-deterministic answer record names.** Reverts the deterministic-upsert pattern introduced by the previous plan's TASK-014 for answers specifically. `MemberProfile` keeps its deterministic naming; this is a scoped reversal, not a convention change.
2. **Nothing else.** Every other task follows existing Space stack conventions verbatim.

---

## Designing for parallel work

The whole point of the wave structure below is that **more than one agent or session can work at the same time without merge conflicts and without a red build**. Two rules make that true:

**Rule 1 — file ownership is exclusive.** Two tasks may run concurrently if and only if their dependencies are satisfied *and* their owned-file sets are disjoint. Every task below declares the files it owns. No file appears in two concurrently-runnable tasks.

**Rule 2 — every task builds and ships alone.** Additive tasks add unused code (green, no behavior change). Cutover tasks switch a call site atomically. Deletion tasks come last. No task depends on a *later* task to compile.

**TASK-001 is the unblocker and should land first, alone.** `SpaceThreadView.swift` is a 503-line file holding three structs — `SpaceThreadView`, `SpaceAllResponsesView`, and `AnswerBubble`. While they share one file, every UI task in this plan serializes on it and any two concurrent UI branches conflict. Splitting it into three files is a pure move with no behavior change, and it converts the entire UI phase from sequential to parallel. Do it first; do it by itself.

**The one deliberate serialization point is TASK-009**, the view model cutover. `SpaceThreadViewModel` state and actions are too entangled to split across two PRs — its state shape and its `submit()` path have to change together or the file doesn't compile. It is one atomic task on purpose, and it is the gate between the data waves and the UI waves.

---

## Wave 0 — Unblock parallelism

**Goal:** the UI file split lands so later waves don't collide. **Runs alone. Effort:** ~1 h.

- [ ] TASK-001: Split `Presentation/Features/Space/Thread/SpaceThreadView.swift` into three files in the same folder — `SpaceThreadView.swift` (the `SpaceThreadView` struct only), `SpaceAllResponsesView.swift`, and `AnswerBubble.swift`. **Pure move: no renames, no signature changes, no behavior change, doc comments travel with their struct.** Add the three files to the Xcode target. Verify the build is green and the app runs identically. (~1 h; deps: none; owns: `Thread/SpaceThreadView.swift`, `Thread/SpaceAllResponsesView.swift`, `Thread/AnswerBubble.swift`, `Reflect.xcodeproj/project.pbxproj`)

**Acceptance:** build green; `git diff --stat` shows moves only; thread and all-feedback screens behave exactly as before.

---

## Wave 1 — Four independent tracks (fully parallel)

**Goal:** the data plumbing for per-record answers exists unused, and the two view-only revisions ship. **All four tasks may run at the same time — disjoint files, no shared dependencies.** Effort: ~5–7 h total, ~2 h critical path.

- [ ] TASK-002: `Domain/Entities/Space/SpaceAnswer.swift` — add `static func newRecordName(reflectionID:questionId:authorRecordName:) -> String` producing `"answer-<reflectionID>-<questionId>-<authorRecordName>-<uuid>"`. Keep the existing deterministic `recordName(...)` in place, marked `// LEGACY — removed in TASK-013`, so nothing breaks. No other change to the struct: `id` is already the record name and already unique per answer. (~0.5 h; deps: TASK-001 not required — independent; owns: `Domain/Entities/Space/SpaceAnswer.swift`)
- [ ] TASK-003: **Export menu.** In `Thread/SpaceAllResponsesView.swift`, replace the `.confirmationDialog("Export feedback", …)` at the toolbar with a `Menu` labelled `square.and.arrow.up` containing "Export as JSON" and "Export as CSV". Drop `showExportOptions` state and the plain `Button`. Keep `ReflectionShareSheet` presentation and `exportedFileURL` observation exactly as they are. (~0.5 h; deps: TASK-001; owns: `Thread/SpaceAllResponsesView.swift`)
- [ ] TASK-004: **Horizontal header.** In `Thread/SpaceThreadView.swift`, rebuild the `header` computed property: `HStack(alignment: .top)` with a left `VStack` (title `.lineLimit(3)`, note `.lineLimit(3)`) and the photo on the right as an 88×88 `.fill` square with `Constants.CornerRadius.medium`; byline and relative time stay below the HStack, full width. Preserve the `fullScreenCover` / `ImageFullscreenViewer` behavior and the "Attached photo" accessibility label. Add tap-to-expand on the note (toggle `lineLimit(3)` ↔ `nil`) so clamped context isn't lost. Constants tokens only. (~1.5 h; deps: TASK-001; owns: `Thread/SpaceThreadView.swift`)
- [ ] TASK-005: **Export gains `answerIndex`.** In `Domain/UseCases/Space/ExportFeedbackRequestUseCase.swift`, add an `answerIndex: Int` to `FeedbackAnswerExport` (0-based, per question per member, ordered by `modifiedAt ?? createdAt`) and add an `answerIndex` column to the CSV row and its `member,answer,photo,timestamp` header. `FeedbackAnswerExport.init(from:)` can't compute the index alone — add an `init(from:answerIndex:)` and assign at the two map sites. JSON gains the field automatically via `Codable`. (~1.5 h; deps: none; owns: `Domain/UseCases/Space/ExportFeedbackRequestUseCase.swift`)

**Acceptance:** build green after each; export menu opens under the toolbar button with no dimming; header is ~110pt shorter with the photo on the right; both export formats carry `answerIndex`; `newRecordName` exists and is called by nothing yet.

---

## Wave 2 — Service and repository (sequential pair, parallel with Wave 1)

**Goal:** create/update answer paths exist end to end, unused. **Effort:** ~4–5 h.

- [ ] TASK-006: `Services/Space/SpaceCloudService.swift` + `SpaceCloudServiceProtocol.swift` — add two methods beside `upsertAnswer` (do not modify it): `createAnswer(to reflection:questionId:text:imageData:in zone:) async throws -> SpaceAnswer` (mint via `SpaceAnswer.newRecordName`, build with `SpaceRecordMapper.makeAnswerRecord`, save, map back) and `updateAnswer(id:text:imageData:in zone:) async throws -> SpaceAnswer` (fetch by record ID, rewrite `text` and the asset — nil clears it, per the existing comment — save, map back; throw `SpaceError.answerNotFound` on `.unknownItem`). Reuse the existing `withRetry` and `makeImageAsset` helpers. `SpaceRecord.swift` should need no change — `makeAnswerRecord` already takes `recordName`; verify rather than assume. (~2 h; deps: TASK-002; owns: `Services/Space/SpaceCloudService.swift`, `Services/Space/SpaceCloudServiceProtocol.swift`)
- [ ] TASK-007: `Data/Repositories/Implementations/SpaceRepository.swift` + `Protocols/SpaceRepositoryProtocol.swift` — add `createAnswer(to:questionId:text:imageData:in:)` and `updateAnswer(_ answer:text:imageData:in:)`, both cloud-first then `try upsertAnswer(answer)` into the cache and `try modelContext.save()`, mirroring the existing public `upsertAnswer` exactly. Leave the public `upsertAnswer` and the private cache-write helper of the same name untouched. No delta, prune, or `CachedAnswer` changes. (~1.5 h; deps: TASK-006; owns: `Data/Repositories/Implementations/SpaceRepository.swift`, `Data/Repositories/Protocols/SpaceRepositoryProtocol.swift`)
- [ ] TASK-008: Use cases + DI — in `Domain/UseCases/Space/UpsertAnswerUseCase.swift`, extend the existing protocol with `create(to:in:questionId:text:image:)` and `update(answer:in:text:image:)` alongside `execute(...)`, sharing the current trim/length validation and `.low` image compression. Keeping both on the one class matches how `DeleteOwnSpaceContentUseCase` carries overloads. Rename the file and type to `AnswerWriteUseCase` only in TASK-013, not here. Add nothing new to `DIContainer` — the existing `makeUpsertAnswerUseCase` factory already vends the type. (~1 h; deps: TASK-007; owns: `Domain/UseCases/Space/UpsertAnswerUseCase.swift`)

**Acceptance:** build green; a second answer to the same question can be created through the repository without overwriting the first (verifiable from `SpaceDebugView` or a scratch call); nothing in the UI calls the new paths yet.

---

## Wave 3 — View model cutover (atomic, the one serialization point)

**Goal:** `SpaceThreadViewModel` stops being keyed one-answer-per-question. **Runs alone. Effort:** ~3 h.

- [ ] TASK-009: **(largest task — must land atomically)** Rewrite `Thread/SpaceThreadViewModel.swift` around answer ids:
  - **State:** replace `activeQuestionId: String?` with a non-optional `selectedQuestionId: String` (seeded to the first question — the segmented control always has a selection); add `editingAnswerID: String?`. Delete `isEditingExistingAnswer` in favor of `editingAnswerID != nil`.
  - **Computed:** replace `myAnswer(for:)` with `myAnswers(for questionId:) -> [SpaceAnswer]` sorted by `modifiedAt ?? createdAt` ascending; keep `answers(for:)` but sort it the same way; delete `answeredQuestionIds`'s binary use and expose `myAnswerCount(for questionId:) -> Int` for the segment dot; `canPost` drops the `activeQuestionId != nil` clause.
  - **Actions:** `select(questionId:)` only changes selection and no longer prefills the composer; add `beginEditing(_ answer: SpaceAnswer)` (sets `editingAnswerID`, prefills `draft`/`draftImage`) and `cancelEditing()`; `submit()` routes to `update` when `editingAnswerID != nil` else `create`, replacing-or-appending in `answers` as it does today, then clears draft, photo, and `editingAnswerID` — **and no longer auto-advances**; `deleteOwnAnswer(for questionId:)` becomes `deleteOwnAnswer(_ answer: SpaceAnswer)`, clearing the composer only when that answer was being edited.
  - **Delete:** `firstUnansweredQuestionId()` and `clearDraftPrefill()`.
  - **Keep:** `load`/`refresh`, `applyEditedReflection` (retarget its stale-selection guard to `selectedQuestionId`), `export`, `registerMyDisplayNameIfKnown`, all haptics.

  The three view files still compile against this only if their call sites are updated in the same commit — they are not; instead, land this task with the *views temporarily calling the new API in the minimal way that compiles* (e.g. `myAnswers(for:).first` where a single answer was shown), and let Wave 4 do the real UI. Build must be green at the end of this task. (~3 h; deps: TASK-008, TASK-001; owns: `Thread/SpaceThreadViewModel.swift`, plus minimal compile-fix edits in the three Thread view files)

**Acceptance:** build green; posting twice to one question creates two records and both appear after refresh; deleting one leaves the other; existing screens still work, if not yet redesigned.

---

## Wave 4 — UI restructure (three parallel tracks)

**Goal:** the sketch, built. **All three tasks may run at the same time — disjoint files after TASK-001.** Effort: ~6–8 h total, ~3.5 h critical path.

- [ ] TASK-010: **Thread view.** In `Thread/SpaceThreadView.swift`, delete `questionsSection` and replace it with: a segmented `Picker` bound to `viewModel.selectedQuestionId` (rendered only when `questions.count > 1`, matching `SpaceAllResponsesView`'s existing pattern, with a small sage dot on segments where `myAnswerCount(for:) > 0`), the selected question's full text below it, a "Your answers / N" label row, and a `ForEach` of `viewModel.myAnswers(for: selectedQuestionId)` rendered as `AnswerBubble`. Simplify `composerBar`: delete `replyingToChip` entirely, drop every `activeQuestionId == nil` disabled state, and add a caption reading "Posting to Q\(n)" or "Editing your answer" with a cancel affordance when `editingAnswerID != nil`. Move the delete confirmation to key off an answer id rather than the `(questionId, number)` tuple, with copy "Delete this answer? This can't be undone." (~3.5 h; deps: TASK-009, TASK-004; owns: `Thread/SpaceThreadView.swift`)
- [ ] TASK-011: **Answer bubble.** In `Thread/AnswerBubble.swift`, change `onEdit` to `(SpaceAnswer) -> Void` and `onDelete` to `(SpaceAnswer) -> Void`; drop the `questionNumber` parameter and change the confirmation copy to "Delete this answer? This can't be undone." Keep the own-vs-others styling, the photo thumbnail with fullscreen viewer, and `ReportContentButton` exactly as they are. (~1.5 h; deps: TASK-009; owns: `Thread/AnswerBubble.swift`)
- [ ] TASK-012: **All feedback.** In `Thread/SpaceAllResponsesView.swift`, keep the segmented control and switch the list to the id-sorted `viewModel.answers(for:)`; route `onEdit` through `viewModel.beginEditing(answer)` before `dismiss()` so the composer opens on the right answer, and `onDelete` through `deleteOwnAnswer(_ answer:)`. Bylines repeat per answer — no author grouping (decision 3). Update the `.onChange(of: viewModel.reflection.questions)` stale-tag guard for the now non-optional `selectedQuestionId`. (~1.5 h; deps: TASK-009, TASK-011, TASK-003; owns: `Thread/SpaceAllResponsesView.swift`)

**Acceptance:** matches the sketch; two answers to Q1 both visible and independently editable; switching segments switches the answer list; single-question requests show no segmented control; editing from the all-feedback list lands on the correct answer.

---

## Wave 5 — Cleanup and verification

**Goal:** the additive scaffolding is gone; the flow is verified across two accounts. **Effort:** ~3–4 h.

- [ ] TASK-013: Remove the transitional surface in one commit — `upsertAnswer` from `SpaceCloudService(+Protocol)` and `SpaceRepository(+Protocol)`, the `execute(...)` upsert method from the use case (rename the file and type `UpsertAnswerUseCase` → `AnswerWriteUseCase`, updating its `DIContainer` factory to `makeAnswerWriteUseCase` and the `SpaceThreadViewModel` dependency name), and the legacy deterministic `SpaceAnswer.recordName(...)`. Compiler-driven sweep; these must land together or the build breaks. (~1.5 h; deps: TASK-010, 011, 012; owns: `SpaceCloudService.swift`, `SpaceCloudServiceProtocol.swift`, `SpaceRepository.swift`, `SpaceRepositoryProtocol.swift`, `UpsertAnswerUseCase.swift` → `AnswerWriteUseCase.swift`, `DIContainer.swift`, `SpaceAnswer.swift`, `SpaceThreadViewModel.swift`)
- [ ] TASK-014: End-to-end verification on two simulators / two accounts (owner + member): post three answers to one question from one account → edit the middle one → delete the first → confirm the other two are untouched on the second device after sync → attach a photo to a second answer → switch segments → owner deletes a question and confirms the cascade removes all of that question's answers, not just one per member → both exports, checking `answerIndex` increments per member per question → kill and relaunch for cache-first paint. Fix what's found, then update [space-progress.md](space-progress.md) and check this list done. (~2 h; deps: everything; owns: `docs/features/space-progress.md`, this file)

**Acceptance:** `grep -rn "upsertAnswer\|firstUnansweredQuestionId\|activeQuestionId" Reflect/` returns nothing; full flow verified across two accounts; docs current.

---

## Dependency graph

```
TASK-001 (file split) ─────┬──────────────────────────────────────────┐
                           │                                          │
        TASK-002 ──────────┼── TASK-006 ── TASK-007 ── TASK-008 ──┐   │
        (independent)      │                                      │   │
                           ├── TASK-003 (export menu) ────────┐    │   │
                           └── TASK-004 (header) ──────────┐  │    │   │
        TASK-005 (export index, independent)               │  │    │   │
                                                           │  │    │   │
                                        TASK-009 (VM cutover) ◄────┴───┘
                                                     │
                            ┌────────────────────────┼───────────────┐
                            │                        │               │
                       TASK-010 ◄──────────────┘  TASK-011      TASK-012
                       (thread)                   (bubble)  ◄─── (all feedback) ◄─ TASK-003
                            │                        │               │
                            └────────────┬───────────┴───────────────┘
                                    TASK-013 (cleanup)
                                         │
                                    TASK-014 (verify)
```

## Parallel schedule

Assuming one agent per track, all tracks building against the same branch point:

| Slot | Concurrent tasks | Wall clock |
|---|---|---|
| 1 | TASK-001 alone | ~1 h |
| 2 | TASK-002 ‖ TASK-003 ‖ TASK-004 ‖ TASK-005 | ~1.5 h |
| 3 | TASK-006 → TASK-007 → TASK-008 (one track, sequential) | ~4.5 h |
| 4 | TASK-009 alone | ~3 h |
| 5 | TASK-010 ‖ TASK-011 ‖ TASK-012 | ~3.5 h |
| 6 | TASK-013 → TASK-014 | ~3.5 h |
| | **Total serial ~22–27 h** | **~17 h parallel** |

TASK-005 has no dependencies at all and can be pulled into any earlier slot. TASK-002 likewise — it's listed in slot 2 only because slot 1 runs alone by policy.

## Effort summary

| Wave | Tasks | Estimate | Parallelism |
|---|---|---|---|
| 0 Unblock | 001 | ~1 h | runs alone |
| 1 Independent tracks | 002–005 | ~4 h | 4-way |
| 2 Service + repo | 006–008 | ~4.5 h | sequential track |
| 3 VM cutover | 009 | ~3 h | runs alone |
| 4 UI restructure | 010–012 | ~6.5 h | 3-way |
| 5 Cleanup + verify | 013–014 | ~3.5 h | sequential |
| **Total** | **14 tasks** | **~22–27 h** | **~17 h with 3–4 concurrent** |

## Running this as an autonomous loop

Same contract as the previous plan. Each tick: open this checklist, find the first `- [ ] TASK-…` whose deps are all checked, implement exactly that task and only the files it owns, run

```bash
xcodebuild -project Reflect.xcodeproj -scheme Reflect \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -configuration Debug build 2>&1 | grep "error:"
```

until the grep is empty, commit that task's files by name (short imperative subject, why-focused body, no `git add -A`, never push), check the box here in the same commit, stop.

**For concurrent runs:** each agent takes a task whose owned-file set is disjoint from every in-flight task's, works on its own branch off the shared base, and merges when green. The owned-file lists are the conflict contract — if two agents need the same file, one waits. TASK-001, TASK-009, and TASK-013 are exclusive: no other task may be in flight while they are, because each rewrites files that later tasks own. TASK-014 contains manual two-device steps — do the code and doc parts, then surface the verification to the user rather than skipping it silently.

Tasks are ordered so plain top-to-bottom sequential consumption never violates a dependency, for when only one agent is running.

## Critical files

| File | Touched by |
|---|---|
| `Presentation/Features/Space/Thread/SpaceThreadView.swift` | 001, 004, 010 |
| `Presentation/Features/Space/Thread/SpaceAllResponsesView.swift` *(new)* | 001, 003, 012 |
| `Presentation/Features/Space/Thread/AnswerBubble.swift` *(new)* | 001, 011 |
| `Presentation/Features/Space/Thread/SpaceThreadViewModel.swift` | 009, 013 |
| `Domain/Entities/Space/SpaceAnswer.swift` | 002, 013 |
| `Services/Space/SpaceCloudService.swift` + protocol | 006, 013 |
| `Data/Repositories/…/SpaceRepository.swift` + protocol | 007, 013 |
| `Domain/UseCases/Space/UpsertAnswerUseCase.swift` | 008, 013 |
| `Domain/UseCases/Space/ExportFeedbackRequestUseCase.swift` | 005 |
| `App/DIContainer.swift` | 013 |

Untouched by design: `CachedAnswer`, `SpaceStore`, `SpaceZoneDelta` and its reconciliation, `SpaceRecord.swift`, `DeleteOwnSpaceContentUseCase`, `SpaceQuestionListEditor`, `SpaceReflectionEditView(Model)`, the compose sheet in `SpaceDetailView`.
