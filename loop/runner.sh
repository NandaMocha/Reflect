#!/bin/bash
# Agent loop driver. Costs zero tokens — all orchestration logic lives here.
# Usage:  ./loop/runner.sh plan "your goal here"   (breakdown only)
#         ./loop/runner.sh run                     (execute until queue empty)
#
# Adapted from the MargaSatya/Family-Money agent-loop kit for Reflect: tasks
# never push straight to WORK_BRANCH. The state machine is
#   queued -> in_progress -> pr_open -> [review] -> approved -> [merge] -> done
#                                     -> [review] -> queued (revise, branch/PR kept)
# `next` (loop.py) prioritizes approved-awaiting-merge, then pr_open-awaiting-
# review, then ordinary queued work — so PRs never pile up behind new tasks.
set -euo pipefail
cd "$(dirname "$0")/.."                 # repo root
source loop/loop.config
LOCK=loop/.runner.lock
[ -f "$LOCK" ] && { echo "runner already active ($LOCK exists)"; exit 1; }
trap 'rm -f "$LOCK"' EXIT; touch "$LOCK"

# Modified (staged or not) + untracked-but-not-gitignored paths, one per line, sorted.
# Used to detect exactly what a task session touched but didn't commit.
dirty_files() {
  { git diff --name-only; git diff --cached --name-only; git ls-files --others --exclude-standard; } | sort -u
}

python3 loop/loop.py init >/dev/null

if [ "${1:-}" = "plan" ]; then
  GOAL="${2:?usage: runner.sh plan \"goal\"}"
  claude -p "$(cat loop/templates/plan.txt)

GOAL: $GOAL" --model "$MODEL_CONTROL" --max-turns "$TURNS_CONTROL" --permission-mode acceptEdits --allowedTools "Bash"
  python3 loop/loop.py status
  exit 0
fi

while true; do
  NEXT=$(python3 loop/loop.py next)
  case "$NEXT" in
    EMPTY)
      echo "== queue empty =="; python3 loop/loop.py status; break ;;
    REPLAN)
      # A replanner session runs under --permission-mode acceptEdits, which lets
      # it edit files but can deny it Bash (python3/sqlite3) entirely — in that
      # case it cannot operate the queue it was dispatched to fix, and instead
      # encodes its fix as an executable loop/REPLAN-*.sh for the runner (which
      # has the human's own shell) to apply. Apply any pending ones before
      # dispatching yet another replanner into the same wall.
      REPLAN_APPLIED=0
      for RS in loop/REPLAN-*.sh; do
        [ -e "$RS" ] || continue
        echo "== applying pending replan script $RS =="
        bash "$RS"
        mv "$RS" "$RS.applied"   # scripts add tasks — not idempotent, never re-run
        REPLAN_APPLIED=1
      done
      if [ "$REPLAN_APPLIED" -eq 1 ]; then continue; fi
      echo "== too many blocked tasks: calling replanner =="
      claude -p "$(cat loop/templates/replan.txt)" \
        --model "$MODEL_CONTROL" --max-turns "$TURNS_CONTROL" --permission-mode acceptEdits --allowedTools "Bash"
      # If the replanner neither fixed the queue in-session nor left a script,
      # looping would dispatch replanners forever. Stop and hand it to the human.
      if [ "$(python3 loop/loop.py next)" = "REPLAN" ] && ! ls loop/REPLAN-*.sh >/dev/null 2>&1; then
        echo "== replanner ran but queue still stalled and no REPLAN-*.sh left — human needed =="
        python3 loop/loop.py status
        exit 1
      fi ;;
    *)
      ID=$(echo "$NEXT"     | python3 -c 'import sys,json;print(json.load(sys.stdin)["id"])')
      TIER=$(echo "$NEXT"   | python3 -c 'import sys,json;print(json.load(sys.stdin)["tier"])')
      BRANCH=$(echo "$NEXT" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("branch") or "")')
      case "$TIER" in
        trivial)   MODEL=$MODEL_TRIVIAL;  TURNS=$TURNS_TRIVIAL;  TPL=task.txt ;;
        standard)  MODEL=$MODEL_STANDARD; TURNS=$TURNS_STANDARD; TPL=task.txt ;;
        complex)   MODEL=$MODEL_COMPLEX;  TURNS=$TURNS_COMPLEX;  TPL=task.txt ;;
        architect) MODEL=$MODEL_CONTROL;  TURNS=$TURNS_CONTROL;  TPL=architect.txt ;;
        review)    MODEL=$MODEL_REVIEW;   TURNS=$TURNS_REVIEW;   TPL=review.txt ;;
        merge)     MODEL=$MODEL_TRIVIAL;  TURNS=$TURNS_MERGE;    TPL=merge.txt ;;
      esac
      echo "== task $ID [$TIER] on $MODEL =="

      # Branch selection: a fresh task (no branch yet) starts from WORK_BRANCH and
      # creates its own feat/<ID>-slug branch inside the session. A task that
      # already has a branch — mid-review (review/merge tiers) or sent back for
      # revision (queued again with branch/PR kept) — reuses that exact branch
      # instead of starting over, so review/merge see the real PR and a revision
      # pushes updates to the SAME PR instead of opening a second one.
      if [ -n "$BRANCH" ]; then
        git checkout "$BRANCH"
      else
        git checkout "$WORK_BRANCH"
      fi

      python3 loop/loop.py start "$ID"

      # Snapshot the dirty set before the session runs, so any files it leaves
      # uncommitted afterward (rather than committed to its own branch, per project
      # convention) can be isolated instead of bleeding into the next task's tree.
      DIRTY_BEFORE="$(dirty_files)"

      set +e
      claude -p "$(cat loop/templates/$TPL)

TASK_ID=$ID
WORK_BRANCH=$WORK_BRANCH
TEST_CMD: ${TEST_CMD}
BUILD_CMD: ${BUILD_CMD:-none}
PROJECT_RULES: read ${PROJECT_RULES} and obey it." \
        --model "$MODEL" --max-turns "$TURNS" --permission-mode acceptEdits --allowedTools "Bash"
      EXEC_EXIT=$?
      set -e

      # A session is contracted to end by calling one of loop.py pr/approve/revise/
      # done/block itself. If it didn't — silent completion (exit 0, ran out of
      # turns/budget without finishing its own bookkeeping) or a crash the exit
      # code doesn't explain — the task would otherwise sit at in_progress forever,
      # invisible to `next`. `reap` is idempotent: no-op if the session already
      # recorded a real outcome.
      if [ "$EXEC_EXIT" -ne 0 ]; then
        python3 loop/loop.py reap "$ID" --reason "session exited non-zero (exit $EXEC_EXIT: crash/limit)"
      else
        python3 loop/loop.py reap "$ID" --reason "session exited 0 but never called pr/approve/revise/done/block (silent completion)"
      fi

      # Whether the task finished, blocked, or was reaped: any file this session
      # touched but did not commit must not bleed into the next task's starting
      # tree. Isolate it instead of leaving it to silently mix with whatever the
      # next session does.
      DIRTY_NOW="$(dirty_files)"
      NEW_DIRTY="$(comm -13 <(echo "$DIRTY_BEFORE") <(echo "$DIRTY_NOW"))"
      if [ -n "$NEW_DIRTY" ]; then
        echo "== task $ID left uncommitted changes — stashing before continuing =="
        echo "$NEW_DIRTY" | tr '\n' '\0' | xargs -0 git stash push -u \
          --message "loop-task-$ID-uncommitted (auto-stashed by runner.sh — task ended without a clean commit)" --
      fi

      python3 loop/loop.py export >/dev/null ;;
  esac
done
