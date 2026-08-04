# Multi-Question Feedback Requests — Implementation Plan

Status: **Planned, not started.** Written 2026-08-04 from `~/Downloads/multi-question-feedback-prompt.md`, refined via clarifying questions, and phased by Fable. Designed to be consumed task-by-task by an autonomous loop. Independently reviewed against the live codebase 2026-08-04: all factual claims (struct/CKRecord/method names, file locations) verified correct; one blocking bug found and fixed (TASK-038 originally split a `SpaceZoneDelta.responses` removal from its `SpaceRepository` consumers across two tasks — merged into TASK-038), plus dependency and pattern-consistency fixes to TASK-007, TASK-013, TASK-015, TASK-033.

## Feature summary

A Feedback Request (`SpaceReflection` in code) currently supports only 1 question. This adds 1–5 questions per request, each answerable independently (`SpaceAnswer`, upsert-able per `(questionId, memberId)`), with per-answer photo attachments, requester-editable questions (with cascading delete of orphaned answers), segmented viewing by question, and JSON/CSV export.

## Clarified decisions (final, resolved via user Q&A before this plan was written)

1. **No persisted `Response` record/entity.** Only `Answer` is real; "a member's full set of answers" is a client-side grouping, never stored.
2. **`Question` is embedded on `SpaceReflection`** as a single JSON field (`questionsJSON` → `[SpaceQuestion]`), not a separate CKRecord type.
3. **Per-answer edit AND delete** are both in scope.
4. **Requester can edit questions post-creation** — text, add/remove (≤5), reorder — even after members have answered.
5. **Rewording an answered question** shows a one-time warning (no data change, just confirmation).
6. **Deleting a question with existing answers hard-deletes those answers**, with a strong count-aware confirmation (not blocked, not orphaned).
7. **No migration.** CloudKit schema is still Dev-only (Production deploy is gate H4 in [space-progress.md](space-progress.md), still open) — clean breaking cutover, Dev test data reset is fine.

## Architectural overview (Fable)

**Strategy: additive first, cutover second, delete last.** Because every task must leave the build green for the loop, new types (`SpaceQuestion`, `SpaceAnswer`, `CachedAnswer`, the `Answer` CKRecord surface) are introduced *alongside* the existing `SpaceResponse` stack. The old Response stack keeps compiling until the UI phases have fully migrated off it, and is deleted in the final cleanup phase (Phase 7). One deliberate transitional shim makes this possible: after the `SpaceReflection` cutover (TASK-007), a computed `promptText: String { questions.first?.text ?? "" }` keeps read-only UI call sites compiling until they're individually migrated (removed in TASK-037).

**Data flow (unchanged in shape, changed in types):** CloudKit is source of truth; every mutation goes cloud-first via `SpaceCloudService`, then upserts the `SpaceStore` SwiftData cache in `SpaceRepository`; `fetchChanges`/`SpaceZoneDelta` reconciles. `Answer` slots exactly where `Response` sits today (child of `SpaceReflection`, parent reference action `.none` to carry the CKShare, flattened cache row linked by string ID).

**Upsert key:** deterministic CKRecord ID `answer-<reflectionID>-<questionId>-<authorRecordName>` — upsert = fetch record by ID, create if missing, save. No uniqueness logic anywhere else; the cache mirrors it because `CachedAnswer.id` is the same string and `@Attribute(.unique)`.

### New architectural surface being introduced (flagged per spec's constraint)

1. **Deterministic CKRecord-ID upsert** — first write path that fetch-or-creates by computed record name instead of always minting a UUID (`MemberProfile` already does deterministic naming, but write-once; this is the first true upsert). TASK-014.
2. **Requester question-editing screen with cascading hard delete** — first flow where one user's edit destroys *other members'* records, guarded by a count-aware destructive confirmation; first "owner edits own reflection after creation" flow at all. Phase 5.
3. **CSV export + multi-format export picker** — first CSV builder and first format-choice export (JSON export exists in Settings; share-sheet presentation reuses `ReflectionShareSheet`, so only the builders are new). Phase 6.
4. **Embedded-JSON field on a CKRecord** (`questionsJSON`) — first structured-blob field; encapsulated behind `SpaceQuestion` codec helpers so no call site touches raw JSON. TASK-002/004.

No other new patterns; everything else follows the existing Space stack conventions verbatim.

---

## Phase 0 — Foundation (additive; nothing existing changes behavior)

**Goal:** all new vocabulary types exist and build; zero behavior change. **Effort:** ~5–7 h.

- [x] TASK-001: Add Space multi-question constants to `Core/Utilities/Constants.swift` (`spaceMaxQuestions = 5`, `spaceQuestionTextMaxLength`, `spaceReflectionNoteMaxLength`; reuse `spaceResponseMaxLength` as the answer length limit) and add new `SpaceError` cases to `Domain/Entities/Space/SpaceError.swift` (`tooManyQuestions`, `emptyQuestionText`, `questionTextTooLong`, `noteTooLong`, `answerNotFound`, `notReflectionOwner`) with `LocalizedError` strings. (~0.5 h; deps: none)
- [x] TASK-002: Create `Domain/Entities/Space/SpaceQuestion.swift` — `struct SpaceQuestion: Codable, Identifiable, Hashable, Sendable { id: String; text: String; order: Int }` plus static codec helpers `encodeJSON([SpaceQuestion]) -> String` and `decodeJSON(String) -> [SpaceQuestion]` (sorted by `order`, tolerant of decode failure → `[]`), and a `validate(_:)` helper enforcing 1–5 non-empty questions (throws TASK-001 errors). (~1 h; deps: TASK-001)
- [x] TASK-003: Create `Domain/Entities/Space/SpaceAnswer.swift` — `id, reflectionID, questionId, text, imageData: Data?, authorRecordName, authorDisplayName, createdAt, modifiedAt, isMine` + static `recordName(reflectionID:questionId:authorRecordName:) -> String` producing `"answer-<reflectionID>-<questionId>-<authorRecordName>"`. (~0.5 h; deps: none)
- [x] TASK-004: Extend `Services/Space/SpaceRecord.swift` additively: `SpaceRecordType.answer = "Answer"`; fields `questionId`, `text` (Answer), `note`, `questionsJSON` (SpaceReflection); mapper functions `makeAnswerRecord(...)` (deterministic record name, parent ref to reflection, optional `CKAsset`) and `answer(from record: CKRecord, isMine:) -> SpaceAnswer?` (asset-tolerant read like `spaceReflection(from:)`). Do NOT touch `makeReflectionRecord` yet. (~1.5 h; deps: TASK-003)
- [x] TASK-005: Create `Data/Space/CachedAnswer.swift` (`@preconcurrency @Model`, `#Index` on `reflectionID`, `@Attribute(.unique) id`, `questionId`, author fields, `text`, `@Attribute(.externalStorage) imageData`, timestamps, `isMine`, `lastFetchedAt`, `init(from: SpaceAnswer)`, `toDomain()`) and register it in the `SpaceStore` schema alongside the existing three models. (~1 h; deps: TASK-003)
- [ ] TASK-006: Manual/dev-hygiene task — reset the CloudKit **Development** environment for the Space container (delete existing test zones via the app / CloudKit Dashboard) and document in `docs/features/space-progress.md` that the promptText/Response shape is being replaced with questionsJSON/Answer with no migration (per clarified decision 7). No code. (~0.5 h; deps: none)

**Acceptance:** project builds; app behavior identical; new types unit-usable; dev environment noted as reset-safe.

---

## Phase 1 — Domain + data layer cutover

**Goal:** `SpaceReflection` carries `note` + `questions`; full Answer CRUD exists end-to-end (service → repo → use cases → DI); Response stack still compiles but is no longer the only path. **Effort:** ~12–15 h.

- [x] TASK-007: **(largest task — reflection shape cutover, must land atomically)** Change `SpaceReflection` entity: add `note: String?` and `questions: [SpaceQuestion]`, remove stored `promptText`, add transitional computed `var promptText: String { questions.first?.text ?? "" }` (marked `// TRANSITIONAL — removed in TASK-037`). Update `SpaceRecordMapper.makeReflectionRecord`/`spaceReflection(from:)` to write/read `note` + `questionsJSON` (drop the `promptText` field). Update `CachedSpaceReflection`: add `note: String?`, replace `promptText: String` with `questionsData: Data`. Update `SpaceCloudServiceProtocol`/`SpaceCloudService.createReflection` and `SpaceRepositoryProtocol`/`SpaceRepository.createReflection` signatures to `(title:note:questions:imageData:)`, and `SpaceRepository.upsertReflection`. Update `CreateSpaceReflectionUseCase` input to `(title, note, questions: [SpaceQuestion], image)` with `SpaceQuestion.validate`. Update the single call site `SpaceDetailViewModel.save()` transitionally: wrap `newPrompt` as one `SpaceQuestion(order: 0)`, `note: nil`. This genuinely spans more files/layers than any other task in the plan — build and fix incrementally per file rather than editing everything then attempting one build; if it proves too large for one session, it's acceptable to split into two commits on the same PR (entity+mapper+cache, then service+repo+usecase+VM shim) rather than force one giant diff. (~3 h; deps: TASK-002, 004, 005)
- [x] TASK-008: Sweep remaining `promptText` writers/readers that must not use the shim semantics: fix `SpaceDebugView` probe record (write `questionsJSON` instead of `promptText`), and verify `SpaceDetailView` row + `SpaceThreadView` header still render via the shim (they'll be properly redone in Phases 2–3). (~0.5 h; deps: TASK-007)
- [x] TASK-009: `SpaceCloudService` + protocol: add `upsertAnswer(to reflection: SpaceReflection, questionId: String, text: String, imageData: Data?, in zone: SpaceZoneRef) async throws -> SpaceAnswer` — compute deterministic ID, fetch existing record (tolerate `.unknownItem` → create via `makeAnswerRecord`), set fields/asset (nil image clears the asset), save, map back. (~1.5 h; deps: TASK-004)
- [x] TASK-010: `SpaceCloudService` + protocol: add `updateReflection(id:in:title:note:questions:) async throws -> SpaceReflection` (fetch record, rewrite `title`/`note`/`questionsJSON`, save) — the primitive for requester question editing. Answer deletion reuses the existing generic `deleteRecord(id:in:)`; no new delete primitive needed. (~1 h; deps: TASK-007)
- [x] TASK-011: `SpaceZoneDelta` + `SpaceCloudService.fetchChanges`: add `answers: [SpaceAnswer]` to the delta and parse `Answer` records in the change handler (keep `responses` parsing intact until Phase 7). (~1 h; deps: TASK-004)
- [x] TASK-012: `SpaceRepositoryProtocol` + `SpaceRepository`: add `cachedAnswers(reflectionID:) -> [SpaceAnswer]`, `fetchAnswers(for:in:) async throws -> [SpaceAnswer]`, `upsertAnswer(...)` (cloud-first, then cache upsert by unique id), `deleteOwnAnswer(_:in:)` (cloud `deleteRecord`, then cache row removal). Extend `applyZoneDelta`/`pruneRowsAbsent`/`refreshAuthorNames` to cover `CachedAnswer`, and make reflection deletion also purge cached answers (mirror `removeCachedResponses`). (~2.5 h; deps: TASK-005, 009, 011)
- [x] TASK-013: `SpaceRepository`: add `updateReflectionQuestions(_ reflection:, in space:, title:, note:, questions:) async throws -> SpaceReflection` implementing the **cascade**: diff old vs new question IDs; for each removed questionId, fetch that reflection's answers and delete every matching Answer record in CloudKit, then delete their cache rows; then call `updateReflection` and upsert the reflection cache row. Cloud-first ordering: cascade deletes → reflection save → cache. Since the answer IDs to delete are already known from the fetch, delete them directly by ID rather than routing through any child-discovery/fetch-before-delete path. (~2 h; deps: TASK-010, 012)
- [x] TASK-014: Use cases (new files in `Domain/UseCases/Space/`): `UpsertAnswerUseCase` (trim/length validation, image compression identical to `CreateSpaceReflectionUseCase`'s pipeline, calls repo upsert) and `FetchAnswersUseCase`. Protocol + `struct Input` + `execute` per convention. (~1.5 h; deps: TASK-012)
- [x] TASK-015: Use cases: `DeleteOwnAnswerUseCase` (guards `isMine`) and `UpdateReflectionQuestionsUseCase` (guards `reflection.isMine`, runs `SpaceQuestion.validate`, calls repo cascade method). Deletion already has a precedent in this codebase — `Domain/UseCases/Space/DeleteOwnSpaceContentUseCase.swift` defines `DeleteOwnSpaceContentUseCaseProtocol` with overloaded `execute(reflection:)`/`execute(response:)` methods on one class. Extend that existing protocol/class with an `execute(answer:)` overload instead of creating a new standalone `DeleteOwnAnswerUseCase` class, to match the established pattern. (~1 h; deps: TASK-013)
- [x] TASK-016: Wire everything in `App/DIContainer.swift`: `makeUpsertAnswerUseCase`, `makeFetchAnswersUseCase`, `makeDeleteOwnAnswerUseCase`, `makeUpdateReflectionQuestionsUseCase`; leave existing Response factories in place. (~0.5 h; deps: TASK-014, 015)

**Acceptance:** build green; creating a feedback request stores `questionsJSON` + `note` in CloudKit; Answer upsert/fetch/delete and question-edit-with-cascade all callable through use cases; sync delta reconciles answers; existing UI still functions (single-question via shim).

---

## Phase 2 — Creation UI (up to 5 questions)

**Goal:** the compose sheet in `SpaceDetailView` creates 1–5 questions + optional note. **Effort:** ~5–6 h.

- [x] TASK-017: Create `Presentation/Features/Space/Questions/SpaceQuestionListEditor.swift` — reusable SwiftUI component editing an array of draft questions (bindable `[SpaceQuestion]`-shaped drafts): per-row multiline `TextField` with counter, swipe/button delete, drag reorder (rewrites `order`), "Add Question" button disabled at `Constants.Limits.spaceMaxQuestions` with a "5 of 5" hint. Reused by Phase 5's editor. Constants tokens only, no hardcoded colors. (~2 h; deps: TASK-002)
- [x] TASK-018: `SpaceDetailViewModel`: replace compose state `newPrompt` with `newNote: String` + `newQuestions: [draft]` (seeded with one empty question); update `canSave` (title non-empty ≤ limit, note ≤ limit, 1–5 questions all non-empty ≤ limit); update `save()` to call the new use case input; reset state on success. (~1.5 h; deps: TASK-007, 017)
- [x] TASK-019: `SpaceDetailView` compose sheet: title section unchanged; add optional "Note" section; replace the "Details" prompt field with `SpaceQuestionListEditor`; keep the photo section as-is. (~1 h; deps: TASK-018)
- [x] TASK-020: `SpaceReflectionRow` (in `SpaceDetailView.swift`): replace the shim `promptText` line with first-question text plus a question-count badge (e.g. "3 questions") when `questions.count > 1`; show note nowhere in the row (keeps it scannable). (~0.5 h; deps: TASK-018)

**Acceptance:** can create a feedback request with title, optional note, and 1–5 questions; "Add Question" hard-caps at 5; empty-question and empty-title states disable "Ask"; created record round-trips through sync with questions in order.

---

## Phase 3 — Answering UI (`SpaceThreadView`)

**Goal:** all questions shown at once as cards; composer scoped to `activeQuestionId`; upsert-on-submit with edit prefill; per-answer delete; photo attach on answers. **Effort:** ~9–11 h.

- [x] TASK-021: Rewrite `SpaceThreadViewModel` state layer onto answers: replace `responses: [SpaceResponse]` with `answers: [SpaceAnswer]`; add `activeQuestionId: String?` (default: first unanswered question), `draftImage: UIImage?`, `isEditingExistingAnswer` derived flag; computed helpers `myAnswer(for questionId:)`, `answeredQuestionIds` (mine), `answers(for questionId:)`, `activeQuestion`; swap dependencies to `FetchAnswersUseCase`/`UpsertAnswerUseCase`/`DeleteOwnAnswerUseCase` (keep old ones removed from this VM; DI factory updated). `load()`/`refresh()` use cached/fetched answers. (~2.5 h; deps: TASK-016)
- [x] TASK-022: `SpaceThreadViewModel` actions: `select(questionId:)` (sets active, prefills `draft`/`draftImage` from existing own answer when present, else clears), `submit()` (upsert to `activeQuestionId`, replace-or-append in `answers`, clear draft + photo, auto-advance `activeQuestionId` to next unanswered question), `deleteOwnAnswer(for questionId:)`. Preserve `registerMyDisplayNameIfKnown` behavior. (~1.5 h; deps: TASK-021)
- [x] TASK-023: `SpaceThreadView` header + question cards: header shows title, note (secondary), request photo, author line; below it a card per question (numbered "Q1…Qn", full text, answered checkmark indicator when `myAnswer != nil`, my answer preview inside the card with context-menu Edit/Delete), tap selects it as active with visual highlight. Replace the `yourResponses` section entirely. (~2.5 h; deps: TASK-022)
- [x] TASK-024: Composer bar upgrade: "Replying to: Q2 — <text>" chip above the field (with an ✕ only clearing edit prefill, not deselecting), edit-mode affordance when overwriting an existing answer, photo-attach button (`PhotosPicker`, same load/compress pattern as the compose sheet) with thumbnail + remove, send disabled when no `activeQuestionId`; photo state cleared after submit (already done in VM, verify in view). (~2 h; deps: TASK-023)
- [x] TASK-025: Create `AnswerBubble` view (replacing `ResponseBubble` usage in this file only for now): author line, answer text, optional photo thumbnail with fullscreen viewer, context menu Edit (own) / Delete (own, confirmation) / `ReportContentButton`. Keep `ResponseBubble` file-level struct intact until Phase 7. (~1.5 h; deps: TASK-023)
- [x] TASK-026: Delete-answer confirmation UX: `confirmationDialog` ("Delete your answer to Q2? This can't be undone.") wired to VM delete; haptics per existing pattern. (~0.5 h; deps: TASK-025)

**Acceptance:** member sees all questions at once; answering Q2 then Q4 in any order works; answered cards show the indicator; tapping an answered question prefills composer and submit overwrites (verified as same record ID upstream); a single answer can be deleted without touching others; photo attaches to exactly the active question and clears after send.

---

## Phase 4 — Viewing collected answers (`SpaceAllResponsesView` struct, in place)

**Goal:** segmented filtering by question inside the existing embedded struct in `SpaceThreadView.swift`. **Effort:** ~3–4 h.

- [x] TASK-027: Add `selectedQuestionId: String?` state to the `SpaceAllResponsesView` struct; when `reflection.questions.count > 1` render a segmented `Picker` ("Q1"…"Qn") + the selected question's full text below it; when exactly 1 question, no control, question text as header. (~1.5 h; deps: TASK-021)
- [x] TASK-028: Filter the list by `viewModel.answers(for: selectedQuestionId)` using `AnswerBubble`; per-question empty state ("No answers to this question yet."); own-answer edit routes back through the same upsert flow (reuse `select` + composer navigation, or an inline edit sheet mirroring `SpaceResponseEditSheet` adapted to answers — keep whichever is smaller, the sheet). (~1.5 h; deps: TASK-025, 027)
- [x] TASK-029: Update the toolbar count badge in `SpaceThreadView` to answer-based counts (e.g. distinct answering members or total answers — pick total answers, matching today's semantics). (~0.5 h; deps: TASK-021)

**Acceptance:** with a 3-question request, segment switching filters correctly; 1-question requests show no segmented control; edits/deletes/report work from the all-answers list.

---

## Phase 5 — Requester question editing (new architectural surface, flagged)

**Goal:** owner can edit title/note/questions after creation: rename, add (≤5), remove (cascades), reorder — with the two warning flows. **Effort:** ~6–8 h.

- [x] TASK-030: Create `Presentation/Features/Space/Questions/SpaceReflectionEditViewModel.swift` — `@Observable @MainActor final class`; state: editable title/note/question drafts (seeded from reflection), plus `answers: [SpaceAnswer]` fetched on load to compute per-question answer counts; deps: `UpdateReflectionQuestionsUseCase`, `FetchAnswersUseCase`; computed: `answerCount(for questionId:)`, `editedQuestionIdsWithAnswers` (text changed AND count ≥ 1), `removedQuestionIdsWithAnswers`; `save()` returns updated reflection. DI factory in `DIContainer`. (~2 h; deps: TASK-015, 016)
- [x] TASK-031: Create `Presentation/Features/Space/Questions/SpaceReflectionEditView.swift` — form reusing `SpaceQuestionListEditor` + title/note fields; per-row answer-count caption ("4 answers"); removing a row with answers requires an immediate strong `confirmationDialog`: "Delete this question and its N answers? Members' answers to it will be permanently deleted." (destructive role). (~2 h; deps: TASK-017, 030)
- [x] TASK-032: Save-time one-time warning for reworded answered questions: on Save, if `editedQuestionIdsWithAnswers` non-empty, show alert "N people already answered with the previous wording — their answers stay linked but won't reflect your edit." Confirm → proceed to `save()`; success dismisses and the caller refreshes. (~1 h; deps: TASK-031)
- [x] TASK-033: Entry point: "Edit questions" action for own reflections — context menu on `SpaceReflectionRow` in `SpaceDetailView` (guarded by `isMine`) and a toolbar menu item in `SpaceThreadView` when `reflection.isMine`; after save, propagate the updated reflection into `SpaceThreadViewModel`/`SpaceDetailViewModel` state (make `SpaceThreadViewModel.reflection` `var` and refresh answers, since cascaded answers may be gone). (~1.5 h; deps: TASK-021, 031, 032 — needs TASK-021's answer-based `SpaceThreadViewModel` rewrite to exist before this can refresh `answers` on it)

**Acceptance:** owner can rename/add/remove/reorder post-creation; removing an answered question shows the count-aware destructive confirmation and hard-deletes those answers in CloudKit + cache (verify on a second device/account); rewording an answered question shows the one-time warning and changes no answer data; non-owners never see the entry point; 5-cap enforced in edit too.

---

## Phase 6 — Export (JSON / CSV, whole request, grouped by question)

**Goal:** share-sheet export of the full feedback request regardless of the selected segment. **Effort:** ~5–6 h.

- [x] TASK-034: Create `Domain/UseCases/Space/ExportFeedbackRequestUseCase.swift` with `enum FeedbackExportFormat { json, csv }`; input: reflection + answers (+ note/title). JSON path: `Codable` export structs (request metadata; per-question objects each with question id/text/order and answer rows carrying member record name, display name, text, `hasPhoto`/photo filename reference, ISO-8601 timestamp), `JSONEncoder` configured exactly like `SettingsViewModel.exportData()` (iso8601, prettyPrinted, sortedKeys), write to `FileManager.default.temporaryDirectory`, return URL. (~2 h; deps: TASK-014)
- [x] TASK-035: Add the CSV path to the same use case: one section per question — header line with question number/text, a column-header row (`member,answer,photo,timestamp`), answer rows, blank line between sections; proper CSV escaping (quote wrapping, doubled quotes, newlines-in-answers safe). (~1.5 h; deps: TASK-034)
- [x] TASK-036: Export UI in the `SpaceAllResponsesView` struct: toolbar export button → `confirmationDialog` ("Export as JSON" / "Export as CSV") → run use case for **all** questions (ignore selected segment) → present via the existing `ReflectionShareSheet` (`UIActivityViewController` wrapper; do not introduce `ShareLink`); DI wiring + VM action + error surfacing via `errorAlert`. (~1.5 h; deps: TASK-034, 035, TASK-027)

**Acceptance:** both formats export the entire request grouped by question; CSV opens cleanly in Numbers/Excel with sections separated by blank lines; JSON is stable-ordered; share sheet presents; segment selection has no effect on scope.

---

## Phase 7 — Cleanup, removal of the Response stack, verification

**Goal:** dead code gone; shim gone; docs updated. **Effort:** ~4–5 h.

- [x] TASK-037: Remove the transitional `promptText` computed shim from `SpaceReflection` and fix any remaining references (compiler-driven sweep; expected: none after Phases 2–3, plus `SpaceDebugView` already fixed in TASK-008). (~0.5 h; deps: TASK-020, 023)
- [x] TASK-038: Remove the Response service/data surface: `SpaceRecordType.response` + `body`/`reflectionID` response fields + `makeResponseRecord`/`spaceResponse(from:)` in `SpaceRecord.swift`; `createResponse`/`updateResponse` in `SpaceCloudService(+Protocol)`; `responses` from `SpaceZoneDelta` and its parsing in `fetchChanges`. **Also remove the `delta.responses` consumers in `SpaceRepository.applyZoneDelta` and `pruneRowsAbsent` in the same task/commit** — leaving them in place after removing `SpaceZoneDelta.responses` does not compile, so this must land as one atomic change, not split across TASK-038/039. (~1.5 h; deps: TASK-021, 028)
- [x] TASK-039: Remove the Response domain/data remainder: `SpaceResponse` entity, `CachedSpaceResponse` (+ drop from `SpaceStore` schema — safe: cache-only store, rebuilds from CloudKit), all response methods from `SpaceRepository(+Protocol)`, `CreateSpaceResponseUseCase`/`EditOwnSpaceResponseUseCase`/`FetchSpaceResponsesUseCase`, their `DIContainer` factories, and the now-unused `ResponseBubble`/`SpaceResponseEditSheet` structs in `SpaceThreadView.swift`. (~1.5 h; deps: TASK-038)
- [x] TASK-040: End-to-end verification pass on two simulators/accounts (owner + member): create 5-question request → answer out of order with a photo → edit an answer (overwrite verified upstream) → delete one answer → owner edits questions (reword warning, cascade delete confirmation) → segment filtering → both exports → sync/kill-and-relaunch cache-first paint. Fix anything found; update `docs/features/space-progress.md` (note the Dev-schema breaking change against gate H4) and mark this checklist done. (~1.5 h; deps: everything)

**Acceptance:** `grep -r "SpaceResponse\|promptText\|Response record"` in `Reflect/` returns nothing feature-relevant; full flow works across two accounts; docs current.

---

## Effort summary

| Phase | Tasks | Estimate |
|---|---|---|
| 0 Foundation | 001–006 | ~5–7 h |
| 1 Domain + data | 007–016 | ~12–15 h |
| 2 Creation UI | 017–020 | ~5–6 h |
| 3 Answering UI | 021–026 | ~9–11 h |
| 4 Viewing/filtering | 027–029 | ~3–4 h |
| 5 Question editing | 030–033 | ~6–8 h |
| 6 Export | 034–036 | ~5–6 h |
| 7 Cleanup | 037–040 | ~4–5 h |
| **Total** | 40 tasks | **~49–62 h** |

Phase dependencies: 0 → 1 → (2, 3 in either order, 3 recommended after 2) → 4 (needs 3) → 5 (needs 1, UI reuse from 2) → 6 (needs 4) → 7 (needs all). Phase 5 can run in parallel with 4/6 if desired; the checklist order above is safe run sequentially.

## Running this as an autonomous loop

Each tick: open this checklist doc, find the first `- [ ] TASK-…` whose listed deps are all checked, implement exactly that task, run `xcodebuild -project Reflect.xcodeproj -scheme Reflect -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build` until green, commit that task's files by name (short imperative subject, why-focused body, no `git add -A`, never push), check the box in this doc (committed with the same change), stop. TASK-006 and TASK-040 contain manual/simulator steps — the loop should do the code/doc parts and surface the manual verification to the user rather than skipping silently. Tasks are ordered so plain top-to-bottom consumption never violates a dependency.

### Critical files for implementation
- `Reflect/Services/Space/SpaceRecord.swift`
- `Reflect/Services/Space/SpaceCloudService.swift`
- `Reflect/Data/Repositories/Implementations/SpaceRepository.swift`
- `Reflect/Presentation/Features/Space/Thread/SpaceThreadView.swift` (and its ViewModel)
- `Reflect/App/DIContainer.swift`
