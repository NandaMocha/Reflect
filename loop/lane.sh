#!/bin/bash
# Multi-lane launcher. Runs one runner.sh per git worktree, all sharing ONE
# queue db, so independent tasks execute concurrently instead of end-to-end.
#
# Usage:
#   ./loop/lane.sh start 3      # create/reuse 3 lanes and run them in background
#   ./loop/lane.sh status       # queue + which lanes are alive
#   ./loop/lane.sh stop         # stop all lanes (finishes nothing mid-session)
#   ./loop/lane.sh clean        # remove lane worktrees (only when stopped)
#
# WHY A WORKTREE PER LANE: a lane checks out branches, so lanes cannot share a
# working tree. Git also allows a branch to live in only one worktree at a time,
# which is exactly what keeps two lanes off the same feat/ branch — the loser
# re-polls (see runner.sh's branch-selection block).
#
# WHAT IS SHARED: the queue db only, via LOOP_DB. Everything else — build
# products, checkouts, runner locks — stays per lane. The merge mutex lives
# next to the db so all lanes see the same lock.
#
# HOW MANY LANES: bounded by the plan's dependency graph, not by this script.
# The multi-answer plan fans out to at most 4 independent tasks and has two
# exclusive gates (TASK-001, TASK-009) where every other lane idles, so 2-3 is
# the useful range; more just adds merge-mutex contention.
set -euo pipefail
cd "$(dirname "$0")/.."
REPO_ROOT="$(pwd)"
source loop/loop.config

LANE_DIR="$REPO_ROOT/.claude/worktrees"
QUEUE_DB="$REPO_ROOT/loop/tasks.db"          # the ONE shared queue
PIDS="$REPO_ROOT/loop/.lane-pids"

cmd="${1:-}"

case "$cmd" in
  start)
    N="${2:?usage: lane.sh start <n>}"
    [ -f "$QUEUE_DB" ] || { echo "no queue at $QUEUE_DB — run loop.py init + a seeder first"; exit 1; }
    : > "$PIDS"
    for i in $(seq 1 "$N"); do
      WT="$LANE_DIR/loop-lane-$i"
      if [ ! -d "$WT" ]; then
        echo "== creating lane $i worktree at $WT =="
        # Detached: the lane never needs a branch of its own, and detaching
        # avoids reserving a branch name that a task might want.
        git worktree add --detach "$WT" "origin/$WORK_BRANCH" >/dev/null
      fi
      # Each lane runs ITS OWN copy of the kit (its worktree's loop/), but all
      # of them point LOOP_DB at the one queue in the main checkout.
      echo "== starting lane $i =="
      ( cd "$WT" && LANE_ID="lane-$i" LOOP_DB="$QUEUE_DB" nohup ./loop/runner.sh run \
          > "$REPO_ROOT/loop/lane-$i.log" 2>&1 & echo $! >> "$PIDS" )
      # Stagger: two lanes polling in the same instant just means one loses the
      # claim and re-polls. Harmless, but staggering keeps the logs readable.
      sleep 3
    done
    echo
    echo "$N lanes running. Logs: loop/lane-*.log"
    echo "Watch:  tail -f loop/lane-1.log"
    echo "Status: ./loop/lane.sh status"
    ;;

  status)
    LOOP_DB="$QUEUE_DB" python3 loop/loop.py status || true
    echo
    echo "== lanes =="
    if [ -f "$PIDS" ]; then
      while read -r pid; do
        if kill -0 "$pid" 2>/dev/null; then echo "  pid $pid  ALIVE"; else echo "  pid $pid  exited"; fi
      done < "$PIDS"
    else
      echo "  none started"
    fi
    [ -d "$REPO_ROOT/loop/.merge.lock" ] && echo "  merge mutex: HELD by pid $(cat "$REPO_ROOT/loop/.merge.lock/pid" 2>/dev/null || echo '?')"
    exit 0
    ;;

  stop)
    [ -f "$PIDS" ] || { echo "no lanes recorded"; exit 0; }
    while read -r pid; do
      kill "$pid" 2>/dev/null && echo "stopped $pid" || true
    done < "$PIDS"
    rm -f "$PIDS"
    # A lane killed mid-merge leaves the mutex behind; nothing else can merge
    # until it goes. Safe to clear here because every lane is now dead.
    rm -rf "$REPO_ROOT/loop/.merge.lock"
    echo 'Note: tasks left at in_progress were mid-session. Run `loop.py reap <id>`'
    echo "on them, or let the next lane's replanner surface them."
    ;;

  clean)
    for WT in "$LANE_DIR"/loop-lane-*; do
      [ -d "$WT" ] || continue
      echo "== removing $WT =="
      git worktree remove --force "$WT"
    done
    ;;

  *)
    echo "usage: lane.sh {start <n>|status|stop|clean}"; exit 1 ;;
esac
