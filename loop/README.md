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
chmod +x loop/runner.sh loop/lane.sh         # once
python3 loop/loop.py init                    # create the db
# load a plan doc's tasks — one seeder per plan; see loop.config's PLAN_DOC
# for which plan is currently active, or use `runner.sh plan` for a fresh
# goal instead of an existing plan doc
python3 loop/seed_multi_answer_ui.py
python3 loop/loop.py status                  # inspect the queue
./loop/runner.sh run                         # executes until queue empty
```

Or just tell Claude Code: **"Read loop/README.md and run the loop"** —
Claude runs the setup + `runner.sh run`.

## Running lanes in parallel

`runner.sh run` is one lane: one session at a time, start to finish. To work
several independent tasks at once, use `lane.sh`, which runs one runner per git
worktree against **one shared queue**:

```bash
./loop/lane.sh start 2     # 2 lanes in background, logs at loop/lane-*.log
./loop/lane.sh status      # queue + which lanes are alive + merge-mutex holder
./loop/lane.sh stop        # kill all lanes
./loop/lane.sh clean       # remove the lane worktrees
```

Four things make concurrent lanes safe; all four are inert in a single-lane run:

- **`LOOP_DB`** — lanes share one `tasks.db` instead of each worktree keeping a
  private one. Without it, lanes silently do the same work twice.
- **`loop.py claim`** — `next` and `start` are separate processes, so two lanes
  can read the same ready row. `claim` flips the row to `in_progress` in one
  atomic statement and reports whether *this* caller won. The loser re-polls.
- **Detached base checkout** — git allows a branch in only one worktree, so
  `git checkout develop` would fail in every lane but the first. Fresh tasks
  detach at `origin/<WORK_BRANCH>` instead; executors cut their own branch
  anyway. Lanes also detach after each task so they don't hold a `feat/` branch
  another lane needs for review or merge.
- **Merge mutex** — `gh pr merge` is server-side and safe, but the local work
  after it (pull, build, plan-doc checkoff, push `WORK_BRANCH`) races: one push
  gets rejected non-fast-forward and one build verifies a tree that never
  existed on the remote. An mkdir-based lock beside the db serializes the merge
  tier across lanes.

**How many lanes:** bounded by the plan's dependency graph, not by the kit. A
plan whose critical path is most of its total effort gains little. For the
multi-answer plan (max 4 independent tasks, two exclusive gates where every
other lane idles) 2–3 is the useful range; beyond that lanes mostly queue on
the merge mutex.

Known rough edge: the git stash stack is shared across a repo's worktrees, so
lanes see each other's auto-stash entries in `git stash list`. The runner only
pushes and never pops, so nothing is lost or mixed — the entries carry the task
id in their message.

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
