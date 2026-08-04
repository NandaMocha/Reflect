# Agent Loop — portable autonomous task loop (Reflect adaptation)

Token-efficient loop: one fresh Claude session per task, SQLite bookkeeping via
a tiny Python CLI, cheap models by default, top model only for planning.

**Provenance:** designed in Family-Money, piloted in `_monitor`, copied into
MargaSatya, and adapted here for Reflect on 2026-08-04. `loop.py`/`runner.sh`
gained a PR/review/merge state machine on the way in — see below — everything
else (CLI shape, tiering, replanner, stall detection) is unchanged from the
original kit.

## What's different here vs. the original kit

The original kit committed each task straight onto `WORK_BRANCH`. Reflect
wants a review gate before anything lands on `develop`, so the state machine
grew a step:

```
queued -> in_progress -> pr_open --[review]--> approved --[merge]--> done
                                  --[review]--> queued (revise, branch/PR kept) -> pr_open -> ...
```

- **Executors never push to `develop`.** They branch off `WORK_BRANCH` as
  `feat/<TASK-ID>-<slug>`, do the work, and open a PR (`loop.py pr`).
- **A review-tier session reviews every PR automatically** — loads
  `swiftui-pro` / `swiftdata-pro` / `swift-concurrency-pro` as relevant to
  what actually changed, independently re-runs the build (never trusts the
  executor's claim), and checks scope + convention discipline against
  `CLAUDE.md`. It either `loop.py approve`s (ready to merge) or
  `loop.py revise`s (kicks the task back to `queued` with feedback in the
  brief's context, branch/PR preserved so the next attempt updates the same
  PR instead of opening a new one).
- **A separate merge-tier session does the actual merge**, only after seeing
  an `APPROVED` GitHub review — squash-merges, re-verifies the build on
  `develop` post-merge (catches two approved PRs stepping on each other),
  checks off the task's box in the plan doc, and closes out the task.
- `loop.py next` prioritizes: approved-awaiting-merge → pr_open-awaiting-review
  → ordinary queued work, so the PR queue never backs up behind new tasks.

## Setup in a new project (2 steps)

1. Copy this whole `loop/` folder into the project root.
2. Edit `loop/loop.config` — set TEST_CMD, WORK_BRANCH, SPEC_ENTRY,
   PROJECT_RULES for that project. That's the only file you touch.

`loop/tasks.db`, `loop/LOOP_STATUS.md`, `loop/.runner.lock` are gitignored —
they're this project's run state, not portable kit content.

## How to run

```bash
chmod +x loop/runner.sh                      # once
python3 loop/loop.py init                    # create the db
# load the 40 tasks from docs/features/multi-question-feedback-plan.md —
# see loop/seed_multi_question_feedback.py, or use runner.sh plan for a
# fresh goal instead of an existing plan doc
python3 loop/seed_multi_question_feedback.py
python3 loop/loop.py status                  # inspect the queue
./loop/runner.sh run                         # executes until queue empty
```

Or just tell Claude Code: **"Read loop/README.md and run the loop"** —
Claude runs the setup + `runner.sh run`.

## How it works

- `runner.sh` (zero tokens) picks the next ready item from `tasks.db` — an
  approved PR to merge, an open PR to review, or a queued task to execute —
  and starts a fresh `claude -p` session for it: haiku for trivial/merge,
  sonnet for standard/complex/review, fable for architect/replanning.
- Each session runs `python3 loop/loop.py context ID` once — brief + review
  feedback (if a revision) + notes from prerequisite tasks + recent commits.
  Total startup context stays small, forever — no conversation history
  accumulates across tasks the way a single long-lived `/loop` invocation
  would.
- On finish it calls exactly one of `loop.py pr/approve/revise/done/block`.
  All bookkeeping is one-line CLI calls — sessions never read or edit a log
  file directly.
- A blocked task auto-requeues once, one tier up. Two blocked tasks stop the
  loop and call the Fable replanner. Human-readable state: `loop/LOOP_STATUS.md`
  (now also shows branch/PR links per task).

## CLI reference

```
python3 loop/loop.py init                                  create the db
python3 loop/loop.py add "t" --tier X --brief "b" [--deps 1,2]
python3 loop/loop.py next                                  next ready item | EMPTY | REPLAN
python3 loop/loop.py context ID                             full context for a session
python3 loop/loop.py start ID
python3 loop/loop.py pr ID --branch B --url U               mark PR opened, ready for review
python3 loop/loop.py approve ID --notes "..."                review passed, ready to merge
python3 loop/loop.py revise ID --reason "..."                review requested changes, back to queued
python3 loop/loop.py done ID --handover "..." [--commit SHA] merged / finished
python3 loop/loop.py block ID --reason "..."
python3 loop/loop.py status | export
```

Requires: python3 (stdlib only), git, `gh` (GitHub CLI, authenticated),
Claude Code CLI.

## Watching it run

Nothing here pushes without your say beyond what's already implied by
starting `runner.sh run` — but every PR is real and visible on GitHub as it's
opened, reviewed, and merged. `gh pr list --base develop` at any point shows
exactly what's in flight. `loop/LOOP_STATUS.md` is the same picture from the
loop's own bookkeeping.
