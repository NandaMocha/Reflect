#!/usr/bin/env python3
"""One-off seeder: loads the 14 TASK-NNN items from
docs/features/multi-answer-ui-plan.md into loop/tasks.db via the normal
`loop.py add` CLI (same code path a planner session would use).

Run once: python3 loop/seed_multi_answer_ui.py

Unlike seed_multi_question_feedback.py, this does NOT assume an empty db —
the 40 multi-question tasks are already in there and must be preserved, so
db ids will NOT line up with TASK numbers. The script parses the id back out
of `loop.py add`'s "OK added task <id>" output and resolves deps through that
mapping. Deps always point backwards, so a single forward pass is enough.

Re-running duplicates rows — it does not dedupe. Check `loop.py status`
first if you're unsure whether it already ran.

Tiers follow the plan doc's own effort/complexity notes:
  trivial  = single-file mechanical change, no design judgement
  standard = one-feature-file work with an already-decided design
  complex  = multi-file cutover or a rewrite other tasks depend on
"""
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
LOOP_PY = os.path.join(HERE, "loop.py")

PLAN_DOC = "docs/features/multi-answer-ui-plan.md"

OWNERSHIP_RULE = (
    "PARALLEL-SAFETY CONTRACT: edit ONLY the files this task owns (listed in the plan doc's "
    "'owns:' note for this task). Another agent may be working on a sibling task at the same "
    "time; touching a file you do not own causes a merge conflict. If the task cannot be done "
    "without editing an unowned file, block with that reason rather than editing it."
)

# (label, title, tier, brief, [dep labels])
TASKS = [
    ("TASK-001", "TASK-001: Split SpaceThreadView.swift into three files", "standard",
     f"See {PLAN_DOC} Wave 0. Split Presentation/Features/Space/Thread/SpaceThreadView.swift "
     "(503 lines, three structs) into three files in the same folder: SpaceThreadView.swift "
     "(the SpaceThreadView struct only), SpaceAllResponsesView.swift, and AnswerBubble.swift. "
     "PURE MOVE — no renames, no signature changes, no behavior change; each struct's doc "
     "comment travels with it. Add the two new files to the Xcode target. This task unblocks "
     "all parallel UI work, so keep the diff purely mechanical: `git diff --stat` should show "
     "moves only.", []),

    ("TASK-002", "TASK-002: SpaceAnswer.newRecordName with UUID component", "trivial",
     f"See {PLAN_DOC} Wave 1. In Domain/Entities/Space/SpaceAnswer.swift add "
     "`static func newRecordName(reflectionID:questionId:authorRecordName:) -> String` returning "
     "\"answer-<reflectionID>-<questionId>-<authorRecordName>-<uuid>\". KEEP the existing "
     "deterministic recordName(...) exactly as is, marked `// LEGACY — removed in TASK-013`. "
     "No other change to the struct — `id` is already the record name. Nothing calls the new "
     "function yet; the build stays green and behavior is unchanged.", []),

    ("TASK-003", "TASK-003: Export confirmationDialog -> Menu", "trivial",
     f"See {PLAN_DOC} Wave 1. In Presentation/Features/Space/Thread/SpaceAllResponsesView.swift "
     "replace the `.confirmationDialog(\"Export feedback\", ...)` and its plain toolbar Button "
     "with a `Menu` labelled with the `square.and.arrow.up` image, containing \"Export as JSON\" "
     "and \"Export as CSV\" buttons calling the same viewModel.export(format:) actions. Remove "
     "the now-unused `showExportOptions` state. Leave ReflectionShareSheet presentation and the "
     "exportedFileURL onChange observation exactly as they are.", ["TASK-001"]),

    ("TASK-004", "TASK-004: Horizontal feedback-request header", "standard",
     f"See {PLAN_DOC} Wave 1. In Presentation/Features/Space/Thread/SpaceThreadView.swift rebuild "
     "the `header` computed property: HStack(alignment: .top) with a left VStack holding the "
     "title (.lineLimit(3)) and note (.lineLimit(3)), and the photo on the right as an 88x88 "
     ".fill square clipped with Constants.CornerRadius.medium. Byline + relative time stay below "
     "the HStack at full width. Preserve the fullScreenCover/ImageFullscreenViewer behavior and "
     "the \"Attached photo\" accessibility label. Add tap-to-expand on the note (toggle "
     "lineLimit(3) <-> nil) so clamped context is not lost. Constants tokens only, no hardcoded "
     "colors or spacing.", ["TASK-001"]),

    ("TASK-005", "TASK-005: answerIndex column in feedback export", "standard",
     f"See {PLAN_DOC} Wave 1. In Domain/UseCases/Space/ExportFeedbackRequestUseCase.swift add "
     "`answerIndex: Int` to FeedbackAnswerExport — 0-based, per question per member, ordered by "
     "`modifiedAt ?? createdAt`. The existing init(from:) cannot compute it alone: add "
     "init(from:answerIndex:) and compute the index at the two map sites (exportCSV and "
     "exportJSON). Add an `answerIndex` column to the CSV rows and to the "
     "`member,answer,photo,timestamp` header row. JSON picks the field up automatically via "
     "Codable. Keep the existing CSV escaping helper untouched.", []),

    ("TASK-006", "TASK-006: SpaceCloudService createAnswer + updateAnswer", "complex",
     f"See {PLAN_DOC} Wave 2. In Services/Space/SpaceCloudService.swift and "
     "SpaceCloudServiceProtocol.swift add two methods ALONGSIDE upsertAnswer (do not modify or "
     "remove it): createAnswer(to reflection:questionId:text:imageData:in zone:) -> SpaceAnswer, "
     "which mints a name via SpaceAnswer.newRecordName, builds the record with "
     "SpaceRecordMapper.makeAnswerRecord, saves and maps back; and "
     "updateAnswer(id:text:imageData:in zone:) -> SpaceAnswer, which fetches by record ID, "
     "rewrites text and the image asset (nil clears it, per the existing comment), saves and "
     "maps back, throwing SpaceError.answerNotFound on CKError .unknownItem. Reuse the existing "
     "withRetry and makeImageAsset helpers. SpaceRecord.swift should need NO change since "
     "makeAnswerRecord already takes a recordName parameter — verify this rather than assuming, "
     "and if it does need a change, say so in the handover.", ["TASK-002"]),

    ("TASK-007", "TASK-007: SpaceRepository createAnswer + updateAnswer", "standard",
     f"See {PLAN_DOC} Wave 2. In Data/Repositories/Implementations/SpaceRepository.swift and "
     "Data/Repositories/Protocols/SpaceRepositoryProtocol.swift add createAnswer("
     "to:questionId:text:imageData:in:) and updateAnswer(_ answer:text:imageData:in:). Both are "
     "cloud-first, then `try upsertAnswer(answer)` into the cache and `try modelContext.save()` "
     "— mirror the existing public upsertAnswer implementation exactly. Leave the public "
     "upsertAnswer and the private same-named cache-write helper untouched. Do NOT change "
     "applyZoneDelta, pruneRowsAbsent, refreshAuthorNames, or CachedAnswer — the cache needs no "
     "changes for this feature.", ["TASK-006"]),

    ("TASK-008", "TASK-008: Answer create/update use case methods", "standard",
     f"See {PLAN_DOC} Wave 2. In Domain/UseCases/Space/UpsertAnswerUseCase.swift extend the "
     "existing UpsertAnswerUseCaseProtocol and class with create(to:in:questionId:text:image:) "
     "and update(answer:in:text:image:), alongside the existing execute(...). Both share the "
     "current trim/length validation (SpaceError.bodyRequired / .bodyTooLong against "
     "Constants.Limits.spaceResponseMaxLength) and the .low image compression. Carrying "
     "overloads on one class matches DeleteOwnSpaceContentUseCase's established pattern. Do NOT "
     "rename the file or type yet (that happens in TASK-013) and do NOT add a DIContainer "
     "factory — makeUpsertAnswerUseCase already vends this type.", ["TASK-007"]),

    ("TASK-009", "TASK-009: SpaceThreadViewModel cutover to answer ids", "complex",
     f"See {PLAN_DOC} Wave 3 — this is the largest task and must land atomically. Rewrite "
     "Presentation/Features/Space/Thread/SpaceThreadViewModel.swift around answer ids. STATE: "
     "replace activeQuestionId: String? with non-optional selectedQuestionId: String (seeded to "
     "the first question); add editingAnswerID: String?; delete isEditingExistingAnswer in "
     "favour of `editingAnswerID != nil`. COMPUTED: replace myAnswer(for:) with myAnswers(for "
     "questionId:) -> [SpaceAnswer] sorted ascending by `modifiedAt ?? createdAt`; sort "
     "answers(for:) the same way; add myAnswerCount(for questionId:) -> Int for the segment dot; "
     "drop the activeQuestionId != nil clause from canPost. ACTIONS: select(questionId:) only "
     "changes selection and no longer prefills the composer; add beginEditing(_ answer:) and "
     "cancelEditing(); submit() routes to update when editingAnswerID != nil else create, "
     "replace-or-append in answers, clear draft/photo/editingAnswerID, and NO LONGER "
     "auto-advances; deleteOwnAnswer(for questionId:) becomes deleteOwnAnswer(_ answer:), "
     "clearing the composer only if that answer was being edited. DELETE "
     "firstUnansweredQuestionId() and clearDraftPrefill(). KEEP load/refresh, "
     "applyEditedReflection (retarget its stale-selection guard to selectedQuestionId), export, "
     "registerMyDisplayNameIfKnown, and all haptics. The three Thread view files must be "
     "compile-fixed in the SAME commit, but MINIMALLY — e.g. myAnswers(for:).first where a "
     "single answer was shown. The real UI comes in Wave 4; do not redesign anything here. "
     "Build must be green.", ["TASK-008", "TASK-001"]),

    ("TASK-010", "TASK-010: Thread view segmented control + answer stack", "complex",
     f"See {PLAN_DOC} Wave 4. In Presentation/Features/Space/Thread/SpaceThreadView.swift delete "
     "questionsSection and replace it with: a segmented Picker bound to "
     "viewModel.selectedQuestionId (rendered only when questions.count > 1, matching "
     "SpaceAllResponsesView's existing pattern) with a small Color.primaryDefault dot on "
     "segments where myAnswerCount(for:) > 0; the selected question's full text below it; a "
     "\"Your answers / N\" label row; and a ForEach over viewModel.myAnswers(for: "
     "selectedQuestionId) rendered as AnswerBubble. Simplify composerBar: DELETE replyingToChip "
     "entirely, drop every activeQuestionId == nil disabled state, and add a caption reading "
     "\"Posting to Q<n>\" or \"Editing your answer\" with a cancel affordance when editing. Move "
     "the delete confirmation to key off an answer id instead of the (questionId, number) tuple, "
     "with copy \"Delete this answer? This can't be undone.\" Constants tokens only.",
     ["TASK-009", "TASK-004"]),

    ("TASK-011", "TASK-011: AnswerBubble edit/delete by answer", "standard",
     f"See {PLAN_DOC} Wave 4. In Presentation/Features/Space/Thread/AnswerBubble.swift change "
     "onEdit to (SpaceAnswer) -> Void and onDelete to (SpaceAnswer) -> Void, and remove the "
     "questionNumber parameter. Change the confirmation copy to \"Delete this answer? This "
     "can't be undone.\" — it is ambiguous once a member has several answers to one question. "
     "Keep the own-vs-others styling, the photo thumbnail with its fullscreen viewer, and "
     "ReportContentButton exactly as they are.", ["TASK-009"]),

    ("TASK-012", "TASK-012: All-feedback list off answer ids", "standard",
     f"See {PLAN_DOC} Wave 4. In Presentation/Features/Space/Thread/SpaceAllResponsesView.swift "
     "keep the segmented control and switch the list to the id-sorted viewModel.answers(for:). "
     "Route onEdit through viewModel.beginEditing(answer) before dismiss() so the composer opens "
     "on the correct answer, and onDelete through deleteOwnAnswer(_ answer:). Bylines repeat per "
     "answer — do NOT group consecutive answers by author (deliberate decision: timestamps carry "
     "the sequence). Update the .onChange(of: viewModel.reflection.questions) stale-tag guard "
     "for the now non-optional selectedQuestionId.", ["TASK-009", "TASK-011", "TASK-003"]),

    ("TASK-013", "TASK-013: Remove upsert scaffolding + rename use case", "complex",
     f"See {PLAN_DOC} Wave 5 — must land as ONE commit or the build breaks. Remove upsertAnswer "
     "from SpaceCloudService(+Protocol) and SpaceRepository(+Protocol); remove the execute(...) "
     "upsert method from the use case and rename the file and type UpsertAnswerUseCase -> "
     "AnswerWriteUseCase (updating the DIContainer factory to makeAnswerWriteUseCase and the "
     "SpaceThreadViewModel dependency name); and remove the LEGACY deterministic "
     "SpaceAnswer.recordName(...). Compiler-driven sweep. Afterwards `grep -rn "
     "\"upsertAnswer|firstUnansweredQuestionId|activeQuestionId\" Reflect/` must return nothing. "
     "This task owns files that Wave 4 tasks own, so no other task may be in flight alongside "
     "it.", ["TASK-010", "TASK-011", "TASK-012"]),

    ("TASK-014", "TASK-014: Two-account end-to-end verification", "standard",
     f"See {PLAN_DOC} Wave 5. CONTAINS MANUAL STEPS — do the code/doc parts and surface the "
     "manual verification to the user rather than skipping it silently. Verify on two "
     "simulators/accounts (owner + member): post three answers to one question, edit the middle "
     "one, delete the first, confirm the other two are untouched on the second device after "
     "sync; attach a photo to a second answer; switch segments; owner deletes a question and the "
     "cascade removes ALL of that question's answers, not just one per member; both exports with "
     "answerIndex incrementing per member per question; kill and relaunch for cache-first paint. "
     "Fix what is found, update docs/features/space-progress.md, and check off the boxes in "
     f"{PLAN_DOC}.", ["TASK-013"]),
]


def main():
    ids = {}
    for label, title, tier, brief, dep_labels in TASKS:
        missing = [d for d in dep_labels if d not in ids]
        if missing:
            sys.exit(f"FATAL: {label} depends on unseeded {missing} — fix TASKS order")
        deps = ",".join(str(ids[d]) for d in dep_labels)

        cmd = [sys.executable, LOOP_PY, "add", title, "--tier", tier,
               "--brief", f"{brief}\n\n{OWNERSHIP_RULE}"]
        if deps:
            cmd += ["--deps", deps]

        out = subprocess.run(cmd, capture_output=True, text=True)
        if out.returncode != 0:
            sys.exit(f"FATAL: add failed for {label}:\n{out.stderr}")

        match = re.search(r"OK added task (\d+)", out.stdout)
        if not match:
            sys.exit(f"FATAL: could not parse id from: {out.stdout!r}")
        ids[label] = int(match.group(1))
        print(f"{label} -> db id {ids[label]}  [{tier}]")

    print(f"\nSeeded {len(ids)} tasks. Run `python3 loop/loop.py status` to inspect.")


if __name__ == "__main__":
    main()
