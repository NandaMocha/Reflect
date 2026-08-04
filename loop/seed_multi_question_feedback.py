#!/usr/bin/env python3
"""One-off seeder: loads the 40 TASK-NNN items from
docs/features/multi-question-feedback-plan.md into loop/tasks.db via the
normal `loop.py add` CLI (so it's the same code path a planner session would
use — nothing bypasses loop.py's own DB writes).

Run once: python3 loop/seed_multi_question_feedback.py
Safe to re-run only against a freshly-initialized (empty) db — it does not
dedupe. If tasks.db already has rows, `loop.py init` + a fresh run is on you.

Task ids are assigned by SQLite AUTOINCREMENT in insertion order, so as long
as this script adds TASK-001 first and TASK-040 last (which it does), db id
N == TASK-00N, and the `deps` lists below (copied from the plan doc's own
"deps:" notes) are just those numbers directly.

Tiers are a first-pass mapping from the plan's own complexity notes:
  trivial  = docs/constants/DI-wiring/mechanical single-line changes
  standard = one-feature-file work with an already-decided design
  complex  = multi-file schema/data-layer cutover or foundational VM rewrite
Adjust in loop/loop.py's `tasks` table directly (or re-seed) if a tier feels
wrong once real tasks start running — this mapping wasn't reviewed as
carefully as the plan doc itself.
"""
import subprocess, sys, os

HERE = os.path.dirname(os.path.abspath(__file__))
LOOP_PY = os.path.join(HERE, "loop.py")

PLAN_DOC = "docs/features/multi-question-feedback-plan.md"

# (title, tier, brief, deps)
TASKS = [
    ("TASK-001: Space multi-question constants + SpaceError cases", "trivial",
     f"See {PLAN_DOC} Phase 0 TASK-001. Add spaceMaxQuestions=5, spaceQuestionTextMaxLength, "
     "spaceReflectionNoteMaxLength to Core/Utilities/Constants.swift (reuse spaceResponseMaxLength "
     "as the answer length limit). Add tooManyQuestions, emptyQuestionText, questionTextTooLong, "
     "noteTooLong, answerNotFound, notReflectionOwner cases to Domain/Entities/Space/SpaceError.swift "
     "with LocalizedError strings. No behavior change elsewhere.", ""),

    ("TASK-002: SpaceQuestion domain type + codec/validate helpers", "trivial",
     f"See {PLAN_DOC} Phase 0 TASK-002. Create Domain/Entities/Space/SpaceQuestion.swift: "
     "struct SpaceQuestion: Codable, Identifiable, Hashable, Sendable { id: String; text: String; order: Int }. "
     "Static SpaceQuestion.encodeJSON([SpaceQuestion]) -> String and decodeJSON(String) -> [SpaceQuestion] "
     "(sorted by order, tolerant of decode failure -> []). Static validate(_:) throwing 1-5 non-empty "
     "questions using TASK-001's SpaceError cases.", "1"),

    ("TASK-003: SpaceAnswer domain entity + deterministic record name", "trivial",
     f"See {PLAN_DOC} Phase 0 TASK-003. Create Domain/Entities/Space/SpaceAnswer.swift: "
     "id, reflectionID, questionId, text, imageData: Data?, authorRecordName, authorDisplayName, "
     "createdAt, modifiedAt, isMine. Static SpaceAnswer.recordName(reflectionID:questionId:authorRecordName:) "
     "-> String producing \"answer-<reflectionID>-<questionId>-<authorRecordName>\".", ""),

    ("TASK-004: Answer CKRecord type + mapper functions", "standard",
     f"See {PLAN_DOC} Phase 0 TASK-004. Extend Services/Space/SpaceRecord.swift additively: "
     "SpaceRecordType.answer = \"Answer\"; fields questionId, text (Answer), note, questionsJSON "
     "(SpaceReflection). Add makeAnswerRecord(...) (deterministic record name from TASK-003, parent "
     "reference to the reflection, optional CKAsset) and answer(from record: CKRecord, isMine:) -> "
     "SpaceAnswer? (asset-tolerant, mirror spaceReflection(from:)'s pattern). Do NOT touch "
     "makeReflectionRecord yet — that's TASK-007.", "3"),

    ("TASK-005: CachedAnswer SwiftData model", "trivial",
     f"See {PLAN_DOC} Phase 0 TASK-005. Create Data/Space/CachedAnswer.swift: @preconcurrency @Model, "
     "#Index on reflectionID, @Attribute(.unique) id, questionId, author fields, text, "
     "@Attribute(.externalStorage) imageData, timestamps, isMine, lastFetchedAt, init(from: SpaceAnswer), "
     "toDomain(). Register it in the SpaceStore schema alongside the existing three models.", "3"),

    ("TASK-006: Reset CloudKit Dev environment + doc note (manual)", "trivial",
     f"See {PLAN_DOC} Phase 0 TASK-006. Manual/dev-hygiene, no Swift code. Reset the CloudKit "
     "Development environment for the Space container (delete existing test zones via the app / "
     "CloudKit Dashboard). Add a note to docs/features/space-progress.md that the promptText/Response "
     "shape is being replaced with questionsJSON/Answer with no migration (schema is still Dev-only, "
     "Production deploy is gate H4, not yet done). If you cannot access the CloudKit Dashboard or "
     "perform the reset from this session, document exactly what a human needs to do and block with "
     "that reason rather than skipping silently.", ""),

    ("TASK-007: SpaceReflection cutover to note + questions (largest task, atomic)", "complex",
     f"See {PLAN_DOC} Phase 1 TASK-007 for the full list of call sites. Change SpaceReflection entity: "
     "add note: String?, questions: [SpaceQuestion]; remove stored promptText; add a transitional "
     "computed `var promptText: String { questions.first?.text ?? \"\" }` marked "
     "`// TRANSITIONAL — removed in TASK-037`. Update SpaceRecordMapper.makeReflectionRecord/"
     "spaceReflection(from:) to write/read note + questionsJSON (drop promptText field). Update "
     "CachedSpaceReflection: add note: String?, replace promptText: String with questionsData: Data. "
     "Update SpaceCloudServiceProtocol/SpaceCloudService.createReflection and "
     "SpaceRepositoryProtocol/SpaceRepository.createReflection + upsertReflection signatures to "
     "(title:note:questions:imageData:). Update CreateSpaceReflectionUseCase input to "
     "(title, note, questions: [SpaceQuestion], image) with SpaceQuestion.validate. Update the single "
     "call site SpaceDetailViewModel.save() transitionally: wrap newPrompt as one "
     "SpaceQuestion(order: 0), note: nil. This task MUST leave the build green — it's the pivot point "
     "everything else builds on. This genuinely spans more files/layers than any other task in this "
     "plan — build and fix incrementally per file rather than editing everything then attempting one "
     "build; if it's too large for one session it's fine to land as two commits on the same PR (entity+"
     "mapper+cache, then service+repo+usecase+VM shim) rather than force one giant diff.", "2,4,5"),

    ("TASK-008: Sweep remaining promptText writers (SpaceDebugView)", "trivial",
     f"See {PLAN_DOC} Phase 1 TASK-008. Fix SpaceDebugView's probe record to write questionsJSON "
     "instead of promptText. Verify SpaceDetailView row + SpaceThreadView header still render "
     "correctly via TASK-007's transitional shim (they'll be properly redone in Phases 2-3, don't "
     "rewrite them now — just confirm no crash/compile error).", "7"),

    ("TASK-009: SpaceCloudService.upsertAnswer", "standard",
     f"See {PLAN_DOC} Phase 1 TASK-009. Add upsertAnswer(to reflection: SpaceReflection, questionId: "
     "String, text: String, imageData: Data?, in zone: SpaceZoneRef) async throws -> SpaceAnswer to "
     "SpaceCloudService + its protocol. Compute the deterministic ID from TASK-003, fetch the existing "
     "record (tolerate .unknownItem -> create via makeAnswerRecord from TASK-004), set fields/asset "
     "(nil image clears the asset), save, map back to SpaceAnswer.", "4"),

    ("TASK-010: SpaceCloudService.updateReflection", "standard",
     f"See {PLAN_DOC} Phase 1 TASK-010. Add updateReflection(id:in:title:note:questions:) async throws "
     "-> SpaceReflection to SpaceCloudService + protocol (fetch record, rewrite title/note/"
     "questionsJSON, save). This is the primitive requester question-editing (Phase 5) will call. "
     "Answer deletion reuses the existing generic deleteRecord(id:in:) — do not add a new delete "
     "primitive.", "7"),

    ("TASK-011: Parse Answer records into SpaceZoneDelta/fetchChanges", "standard",
     f"See {PLAN_DOC} Phase 1 TASK-011. Add answers: [SpaceAnswer] to SpaceZoneDelta and parse Answer "
     "records in SpaceCloudService.fetchChanges' change handler. Keep the existing `responses` parsing "
     "intact — it's only removed in Phase 7 (TASK-038).", "4"),

    ("TASK-012: SpaceRepository Answer CRUD + cache reconciliation", "complex",
     f"See {PLAN_DOC} Phase 1 TASK-012. Add to SpaceRepositoryProtocol + SpaceRepository: "
     "cachedAnswers(reflectionID:) -> [SpaceAnswer], fetchAnswers(for:in:) async throws -> [SpaceAnswer], "
     "upsertAnswer(...) (cloud-first via TASK-009, then cache upsert by unique id), "
     "deleteOwnAnswer(_:in:) (cloud deleteRecord, then cache row removal). Extend applyZoneDelta/"
     "pruneRowsAbsent/refreshAuthorNames to cover CachedAnswer, and make reflection deletion also purge "
     "cached answers (mirror the existing removeCachedResponses pattern).", "5,9,11"),

    ("TASK-013: SpaceRepository.updateReflectionQuestions with cascading delete", "complex",
     f"See {PLAN_DOC} Phase 1 TASK-013 — this implements clarified decision 6 (hard-delete, not "
     "orphan, not blocked). Add updateReflectionQuestions(_ reflection:, in space:, title:, note:, "
     "questions:) async throws -> SpaceReflection to SpaceRepository. Diff old vs new question IDs; "
     "for each REMOVED questionId, fetch that reflection's answers and delete every matching Answer "
     "CKRecord in CloudKit, then delete their cache rows; then call updateReflection (TASK-010) and "
     "upsert the reflection cache row. Ordering matters: cascade deletes -> reflection save -> cache. "
     "Since the answer IDs to delete are already known from the fetch, delete them directly by ID "
     "rather than routing through any child-discovery/fetch-before-delete path.", "10,12"),

    ("TASK-014: UpsertAnswerUseCase + FetchAnswersUseCase", "standard",
     f"See {PLAN_DOC} Phase 1 TASK-014. New files in Domain/UseCases/Space/: UpsertAnswerUseCase "
     "(trim/length validation, image compression identical to CreateSpaceReflectionUseCase's pipeline, "
     "calls SpaceRepository.upsertAnswer) and FetchAnswersUseCase. Protocol + struct Input + "
     "execute(input:) async throws per project convention.", "12"),

    ("TASK-015: Answer deletion + UpdateReflectionQuestionsUseCase", "standard",
     f"See {PLAN_DOC} Phase 1 TASK-015. Deletion already has a precedent in this codebase — "
     "Domain/UseCases/Space/DeleteOwnSpaceContentUseCase.swift defines "
     "DeleteOwnSpaceContentUseCaseProtocol with overloaded execute(reflection:)/execute(response:) "
     "methods on one class. Extend that existing protocol/class with an execute(answer:) overload "
     "(guards isMine) instead of creating a new standalone DeleteOwnAnswerUseCase class, to match the "
     "established pattern. Also add UpdateReflectionQuestionsUseCase (new file — no existing precedent "
     "to match here) guarding reflection.isMine, running SpaceQuestion.validate, calling "
     "SpaceRepository.updateReflectionQuestions from TASK-013.", "13"),

    ("TASK-016: Wire Answer/question-editing use cases into DIContainer", "trivial",
     f"See {PLAN_DOC} Phase 1 TASK-016. In App/DIContainer.swift add makeUpsertAnswerUseCase, "
     "makeFetchAnswersUseCase, makeDeleteOwnAnswerUseCase, makeUpdateReflectionQuestionsUseCase. Leave "
     "existing Response factories in place — they're removed in Phase 7.", "14,15"),

    ("TASK-017: SpaceQuestionListEditor reusable component", "standard",
     f"See {PLAN_DOC} Phase 2 TASK-017. Create Presentation/Features/Space/Questions/"
     "SpaceQuestionListEditor.swift: reusable SwiftUI component editing an array of draft questions "
     "(bindable [SpaceQuestion]-shaped drafts). Per-row multiline TextField with character counter, "
     "swipe/button delete, drag reorder (rewrites order), \"Add Question\" button disabled at "
     "Constants.Limits.spaceMaxQuestions with a \"5 of 5\" hint. Will be reused by Phase 5's requester "
     "edit screen. Use Color/Constants tokens only, no hardcoded colors.", "2"),

    ("TASK-018: SpaceDetailViewModel compose-state cutover to questions", "standard",
     f"See {PLAN_DOC} Phase 2 TASK-018. Replace SpaceDetailViewModel's compose state `newPrompt` with "
     "`newNote: String` + `newQuestions: [draft]` (seeded with one empty question). Update `canSave` "
     "(title non-empty <= limit, note <= limit, 1-5 questions all non-empty <= limit). Update `save()` "
     "to call CreateSpaceReflectionUseCase's new (title, note, questions, image) input from TASK-007. "
     "Reset state on success.", "7,17"),

    ("TASK-019: SpaceDetailView compose sheet UI for note + questions", "standard",
     f"See {PLAN_DOC} Phase 2 TASK-019. In the SpaceDetailView compose sheet: keep the title section "
     "unchanged, add an optional \"Note\" section, replace the old \"Details\" prompt field with "
     "SpaceQuestionListEditor (TASK-017), keep the photo section as-is.", "18"),

    ("TASK-020: SpaceReflectionRow first-question + count badge", "trivial",
     f"See {PLAN_DOC} Phase 2 TASK-020. In SpaceReflectionRow (SpaceDetailView.swift), replace the "
     "shim promptText line with the first question's text plus a question-count badge (e.g. "
     "\"3 questions\") when questions.count > 1. Don't show the note in the row — keep it scannable.", "18"),

    ("TASK-021: SpaceThreadViewModel state layer onto SpaceAnswer", "complex",
     f"See {PLAN_DOC} Phase 3 TASK-021 — foundational rewrite the rest of Phase 3/4 depend on. "
     "Replace `responses: [SpaceResponse]` with `answers: [SpaceAnswer]` in SpaceThreadViewModel. Add "
     "activeQuestionId: String? (default: first unanswered question), draftImage: UIImage?, "
     "isEditingExistingAnswer derived flag. Computed helpers: myAnswer(for questionId:), "
     "answeredQuestionIds (mine), answers(for questionId:), activeQuestion. Swap dependencies to "
     "FetchAnswersUseCase/UpsertAnswerUseCase/DeleteOwnAnswerUseCase from TASK-016 (remove the old "
     "Response use-case dependencies from this VM specifically; DI factory for this VM needs updating "
     "to match). load()/refresh() use cached/fetched answers instead of responses.", "16"),

    ("TASK-022: SpaceThreadViewModel select/submit/delete actions", "standard",
     f"See {PLAN_DOC} Phase 3 TASK-022. Add to SpaceThreadViewModel: select(questionId:) (sets active, "
     "prefills draft/draftImage from the member's existing own answer when present, else clears), "
     "submit() (upsert to activeQuestionId via UpsertAnswerUseCase, replace-or-append in `answers`, "
     "clear draft + photo, auto-advance activeQuestionId to the next unanswered question), "
     "deleteOwnAnswer(for questionId:). Preserve the existing registerMyDisplayNameIfKnown behavior.", "21"),

    ("TASK-023: SpaceThreadView header + per-question answer cards", "standard",
     f"See {PLAN_DOC} Phase 3 TASK-023. Rebuild SpaceThreadView's header (title, note secondary, "
     "request photo, author line) and replace the `yourResponses` section entirely with a card per "
     "question: numbered \"Q1...Qn\", full question text, an answered checkmark indicator when "
     "myAnswer != nil, the member's own answer preview inside the card with a context-menu Edit/"
     "Delete, tap selects it as the active question with a visual highlight.", "22"),

    ("TASK-024: ComposerBar \"Replying to\" chip + photo attach", "standard",
     f"See {PLAN_DOC} Phase 3 TASK-024. Composer bar upgrade: a \"Replying to: Q2 — <text>\" chip above "
     "the field (an X on it clears edit prefill without deselecting the question), an edit-mode "
     "affordance when overwriting an existing answer, a photo-attach button (PhotosPicker, same load/"
     "compress pattern as the compose sheet) with thumbnail + remove, send disabled when no "
     "activeQuestionId. Verify photo state is cleared after submit (TASK-022 already does this in the "
     "VM — just confirm the view reflects it).", "23"),

    ("TASK-025: AnswerBubble view", "standard",
     f"See {PLAN_DOC} Phase 3 TASK-025. Create a new AnswerBubble view (used in place of ResponseBubble "
     "in SpaceThreadView.swift only, for now): author line, answer text, optional photo thumbnail with "
     "fullscreen viewer, context menu with Edit (own) / Delete (own, confirmation) / "
     "ReportContentButton. Do NOT delete the old ResponseBubble struct yet — it's removed in TASK-039.", "23"),

    ("TASK-026: Delete-answer confirmation dialog", "trivial",
     f"See {PLAN_DOC} Phase 3 TASK-026. Wire a confirmationDialog (\"Delete your answer to Q2? This "
     "can't be undone.\") to SpaceThreadViewModel.deleteOwnAnswer from TASK-022, with the project's "
     "existing haptics pattern on confirm.", "25"),

    ("TASK-027: Segmented question filter in SpaceAllResponsesView", "standard",
     f"See {PLAN_DOC} Phase 4 TASK-027. In the SpaceAllResponsesView struct embedded inside "
     "SpaceThreadView.swift (there is no standalone SpaceAllResponsesView.swift file — do not create "
     "one), add selectedQuestionId: String? state. When reflection.questions.count > 1, render a "
     "segmented Picker (\"Q1\"...\"Qn\") plus the selected question's full text below it. When exactly "
     "1 question, no control — just the question text as a header.", "21"),

    ("TASK-028: Filter answer list by question + edit routing", "standard",
     f"See {PLAN_DOC} Phase 4 TASK-028. Filter the SpaceAllResponsesView list by "
     "viewModel.answers(for: selectedQuestionId) using AnswerBubble (TASK-025). Add a per-question "
     "empty state (\"No answers to this question yet.\"). Route own-answer edit back through the "
     "upsert flow (reuse select() + composer navigation, or add a small inline edit sheet adapted from "
     "the old SpaceResponseEditSheet — pick whichever is smaller).", "25,27"),

    ("TASK-029: Answer-based count badge in SpaceThreadView toolbar", "trivial",
     f"See {PLAN_DOC} Phase 4 TASK-029. Update SpaceThreadView's toolbar count badge to be answer-"
     "based (total answers, matching today's semantics) instead of response-based.", "21"),

    ("TASK-030: SpaceReflectionEditViewModel (new architectural surface)", "standard",
     f"See {PLAN_DOC} Phase 5 TASK-030 — flagged new surface: first \"owner edits own reflection after "
     "creation\" flow in the app. Create Presentation/Features/Space/Questions/"
     "SpaceReflectionEditViewModel.swift: @Observable @MainActor final class; editable title/note/"
     "question drafts seeded from the reflection, plus answers: [SpaceAnswer] fetched on load to "
     "compute per-question answer counts. Depends on UpdateReflectionQuestionsUseCase + "
     "FetchAnswersUseCase from TASK-016. Computed: answerCount(for questionId:), "
     "editedQuestionIdsWithAnswers (text changed AND count >= 1), removedQuestionIdsWithAnswers. "
     "save() returns the updated reflection. Add a DIContainer factory for it.", "15,16"),

    ("TASK-031: SpaceReflectionEditView + destructive delete confirmation", "standard",
     f"See {PLAN_DOC} Phase 5 TASK-031. Create Presentation/Features/Space/Questions/"
     "SpaceReflectionEditView.swift: a form reusing SpaceQuestionListEditor (TASK-017) plus title/note "
     "fields, a per-row answer-count caption (\"4 answers\"). Removing a row that has answers requires "
     "an immediate strong confirmationDialog (\"Delete this question and its N answers? Members' "
     "answers to it will be permanently deleted.\", destructive role) before it's allowed — this "
     "implements clarified decision 6.", "17,30"),

    ("TASK-032: One-time reworded-question warning", "standard",
     f"See {PLAN_DOC} Phase 5 TASK-032 — implements clarified decision 5. On Save in "
     "SpaceReflectionEditView/ViewModel, if editedQuestionIdsWithAnswers (from TASK-030) is non-empty, "
     "show an alert: \"N people already answered with the previous wording — their answers stay "
     "linked but won't reflect your edit.\" Confirm proceeds to save(); this changes no data, it's "
     "purely a confirmation gate.", "31"),

    ("TASK-033: Entry points for requester question editing", "standard",
     f"See {PLAN_DOC} Phase 5 TASK-033. Add an \"Edit questions\" action for own reflections: a context "
     "menu item on SpaceReflectionRow in SpaceDetailView (guarded by isMine) and a toolbar menu item in "
     "SpaceThreadView when reflection.isMine. After a successful save, propagate the updated reflection "
     "into SpaceThreadViewModel/SpaceDetailViewModel state — make SpaceThreadViewModel.reflection `var` "
     "and refresh its answers, since a cascade may have deleted some.", "21,31,32"),

    ("TASK-034: ExportFeedbackRequestUseCase — JSON path", "standard",
     f"See {PLAN_DOC} Phase 6 TASK-034. Create Domain/UseCases/Space/ExportFeedbackRequestUseCase.swift "
     "with enum FeedbackExportFormat { json, csv }. Input: reflection + answers (+ note/title). JSON "
     "path: Codable export structs (request metadata; per-question objects each with question id/text/"
     "order and answer rows carrying member record name, display name, text, hasPhoto/photo filename "
     "reference, ISO-8601 timestamp). Configure JSONEncoder exactly like "
     "SettingsViewModel.exportData() (iso8601, prettyPrinted, sortedKeys). Write to "
     "FileManager.default.temporaryDirectory, return the URL.", "14"),

    ("TASK-035: ExportFeedbackRequestUseCase — CSV path", "standard",
     f"See {PLAN_DOC} Phase 6 TASK-035. Add the CSV path to TASK-034's use case: one section per "
     "question — a header line with the question number/text, a column-header row "
     "(member,answer,photo,timestamp), the answer rows, a blank separator line between sections. "
     "Proper CSV escaping: quote-wrap fields containing commas/quotes/newlines, double any embedded "
     "quotes.", "34"),

    ("TASK-036: Export UI (format picker + share sheet)", "standard",
     f"See {PLAN_DOC} Phase 6 TASK-036. In the SpaceAllResponsesView struct, add a toolbar export "
     "button -> confirmationDialog (\"Export as JSON\" / \"Export as CSV\") -> run "
     "ExportFeedbackRequestUseCase (TASK-034/035) for ALL questions regardless of the currently "
     "selected segment -> present via the existing ReflectionShareSheet (UIActivityViewController "
     "wrapper — do NOT introduce SwiftUI's ShareLink, this app doesn't use it anywhere). Wire DI + VM "
     "action + error surfacing via the existing errorAlert pattern.", "34,35,27"),

    ("TASK-037: Remove the transitional promptText shim", "trivial",
     f"See {PLAN_DOC} Phase 7 TASK-037. Remove the transitional `promptText` computed property added "
     "in TASK-007 from SpaceReflection. Fix any remaining compiler-flagged references (expected: none "
     "after Phases 2-3 plus TASK-008's SpaceDebugView fix).", "20,23"),

    ("TASK-038: Remove Response service/data surface", "standard",
     f"See {PLAN_DOC} Phase 7 TASK-038. Remove: SpaceRecordType.response + body/reflectionID response "
     "fields + makeResponseRecord/spaceResponse(from:) in SpaceRecord.swift; createResponse/"
     "updateResponse in SpaceCloudService(+Protocol); `responses` from SpaceZoneDelta and its parsing "
     "in fetchChanges. IMPORTANT: also remove the delta.responses consumers in "
     "SpaceRepository.applyZoneDelta and pruneRowsAbsent in this SAME task/commit — leaving them in "
     "place after removing SpaceZoneDelta.responses will not compile. Do not split this across "
     "TASK-038/039; land it as one atomic change here.", "21,28"),

    ("TASK-039: Remove Response domain/data remainder", "standard",
     f"See {PLAN_DOC} Phase 7 TASK-039. Remove: SpaceResponse entity, CachedSpaceResponse (+ drop from "
     "the SpaceStore schema — safe, it's a cache-only store that rebuilds from CloudKit), all response "
     "methods from SpaceRepository(+Protocol), CreateSpaceResponseUseCase/EditOwnSpaceResponseUseCase/"
     "FetchSpaceResponsesUseCase, their DIContainer factories, and the now-unused ResponseBubble/"
     "SpaceResponseEditSheet structs in SpaceThreadView.swift.", "38"),

    ("TASK-040: End-to-end verification pass + docs update", "complex",
     f"See {PLAN_DOC} Phase 7 TASK-040. Two-account/two-simulator verification: create a 5-question "
     "request -> answer out of order with a photo -> edit an answer (confirm overwrite, not "
     "duplicate) -> delete one answer -> owner edits questions (reword warning, cascade-delete "
     "confirmation) -> segment filtering -> both exports -> sync / kill-and-relaunch cache-first "
     "paint. Fix anything found (small, in-scope fixes only — anything larger should block() with a "
     "clear reason instead of silently expanding scope). Update docs/features/space-progress.md "
     "noting this Dev-schema breaking change against gate H4. Run "
     "`grep -rE \"SpaceResponse|promptText|Response record\" Reflect/` and confirm it returns nothing "
     "feature-relevant.", "33,36,37,38,39"),
]

def main():
    subprocess.run([sys.executable, LOOP_PY, "init"], check=True)
    for title, tier, brief, deps in TASKS:
        cmd = [sys.executable, LOOP_PY, "add", title, "--tier", tier, "--brief", brief]
        if deps:
            cmd += ["--deps", deps]
        subprocess.run(cmd, check=True)
    print(f"\nOK seeded {len(TASKS)} tasks.")

if __name__ == "__main__":
    main()
