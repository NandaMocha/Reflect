#!/usr/bin/env python3
"""Agent loop bookkeeping CLI. Zero dependencies (stdlib only).

Adapted from the MargaSatya/Family-Money agent-loop kit for Reflect, with a
PR/review/merge state machine added: executors never push to WORK_BRANCH
directly, they open a PR; a dedicated review-tier session (SwiftUI-aware)
approves or requests changes; a dedicated merge-tier session performs the
actual merge only after approval.

State machine per task:
  queued -> in_progress -> pr_open -> (review) -> approved -> (merge) -> done
                                    -> (review) -> queued [revise, branch/PR kept] -> pr_open -> ...
  any non-terminal state -> blocked (escalates tier once, then stays blocked)

Every command is a cheap one-liner for a Claude session:
  python3 loop/loop.py init
  python3 loop/loop.py add "title" --tier standard --brief "..." [--deps 1,2]
  python3 loop/loop.py next            -> JSON of next ready task | EMPTY | REPLAN
  python3 loop/loop.py context ID      -> everything a fresh session needs, one call
  python3 loop/loop.py start ID
  python3 loop/loop.py pr ID --branch B --url U        -> mark PR opened, ready for review
  python3 loop/loop.py approve ID --notes "..."        -> review passed, ready to merge
  python3 loop/loop.py revise ID --reason "..."        -> review requested changes, back to queued (branch/PR kept)
  python3 loop/loop.py done ID --handover "..." [--commit SHA]
  python3 loop/loop.py block ID --reason "..."
  python3 loop/loop.py reap ID --reason "..."   -> no-op unless still in_progress, then blocks
  python3 loop/loop.py status
  python3 loop/loop.py export          -> LOOP_STATUS.md for humans
"""
import argparse, glob, json, os, sqlite3, subprocess, sys, datetime

HERE = os.path.dirname(os.path.abspath(__file__))
DB = os.path.join(HERE, "tasks.db")
HANDOVER_MAX = 400          # hard cap: chars
REPLAN_THRESHOLD = int(os.environ.get("BLOCKED_REPLAN_THRESHOLD", "2"))
ESCALATE = {"trivial": "standard", "standard": "complex", "complex": "architect"}

def db():
    con = sqlite3.connect(DB)
    con.row_factory = sqlite3.Row
    return con

def now():
    return datetime.datetime.now().isoformat(timespec="seconds")

def cmd_init(_):
    con = db()
    con.execute("""CREATE TABLE IF NOT EXISTS tasks (
        id INTEGER PRIMARY KEY, title TEXT NOT NULL, brief TEXT NOT NULL,
        tier TEXT NOT NULL CHECK (tier IN ('trivial','standard','complex','architect')),
        status TEXT NOT NULL DEFAULT 'queued'
          CHECK (status IN ('queued','in_progress','pr_open','approved','done','blocked','split','cancelled')),
        depends_on TEXT DEFAULT '', attempts INTEGER DEFAULT 0,
        handover TEXT DEFAULT '', commit_sha TEXT DEFAULT '',
        branch TEXT DEFAULT '', pr_url TEXT DEFAULT '',
        created_at TEXT, updated_at TEXT)""")
    con.commit()
    # Additive migration for DBs created before branch/pr_url existed.
    cols = {r[1] for r in con.execute("PRAGMA table_info(tasks)")}
    if "branch" not in cols:
        con.execute("ALTER TABLE tasks ADD COLUMN branch TEXT DEFAULT ''")
    if "pr_url" not in cols:
        con.execute("ALTER TABLE tasks ADD COLUMN pr_url TEXT DEFAULT ''")
    con.commit()
    print("OK db ready:", DB)

def cmd_add(a):
    con = db()
    cur = con.execute(
        "INSERT INTO tasks (title, brief, tier, depends_on, created_at, updated_at) VALUES (?,?,?,?,?,?)",
        (a.title, a.brief, a.tier, a.deps or "", now(), now()))
    con.commit()
    print(f"OK added task {cur.lastrowid}: [{a.tier}] {a.title}")

def deps_done(con, row):
    ids = [d.strip() for d in (row["depends_on"] or "").split(",") if d.strip()]
    if not ids:
        return True
    q = ",".join("?" * len(ids))
    n = con.execute(f"SELECT COUNT(*) FROM tasks WHERE id IN ({q}) AND status IN ('done','split','cancelled')", ids).fetchone()[0]
    return n == len(ids)

def apply_pending_replans():
    """Replanner sessions run under a permission mode that can deny them Bash
    (python3/sqlite3) entirely; when it does, they encode their queue fix as an
    executable loop/REPLAN-*.sh for the runner's own unrestricted shell to
    apply. runner.sh's REPLAN branch applies these too, but a runner process
    started before that fix landed keeps executing its original loop body
    forever — bash parses the whole `while` compound before running it, so
    mid-run edits to runner.sh never reach a live runner. `next` is the one
    hook every runner, old or new, re-reads from disk each iteration, so the
    apply step lives here as well. Scripts add tasks — never idempotent, never
    re-run: renamed *.applied on success, *.failed on failure (a half-applied
    script must not run twice; a human resolves it). All script output goes to
    stderr — the runner captures next's stdout and must see only JSON/EMPTY/REPLAN."""
    for rs in sorted(glob.glob(os.path.join(HERE, "REPLAN-*.sh"))):
        res = subprocess.run(["bash", rs], capture_output=True, text=True)
        ok = res.returncode == 0
        os.rename(rs, rs + (".applied" if ok else ".failed"))
        sys.stderr.write(res.stdout + res.stderr)
        sys.stderr.write(f"== {os.path.basename(rs)} {'applied' if ok else 'FAILED (exit ' + str(res.returncode) + ') — renamed *.failed, will not re-run; human review needed'} ==\n")

def cmd_next(_):
    apply_pending_replans()
    con = db()
    blocked = con.execute("SELECT COUNT(*) FROM tasks WHERE status='blocked'").fetchone()[0]
    if blocked >= REPLAN_THRESHOLD:
        print("REPLAN"); return

    # Priority 1: an approved PR waiting to be merged — cheapest, fastest to clear.
    row = con.execute("SELECT * FROM tasks WHERE status='approved' ORDER BY id LIMIT 1").fetchone()
    if row:
        print(json.dumps({"id": row["id"], "tier": "merge", "title": row["title"], "branch": row["branch"]}))
        return

    # Priority 2: an open PR waiting for review — keep the review queue short.
    row = con.execute("SELECT * FROM tasks WHERE status='pr_open' ORDER BY id LIMIT 1").fetchone()
    if row:
        print(json.dumps({"id": row["id"], "tier": "review", "title": row["title"], "branch": row["branch"]}))
        return

    # Priority 3: normal work — first queued task whose deps are satisfied.
    for row in con.execute("SELECT * FROM tasks WHERE status='queued' ORDER BY id"):
        if deps_done(con, row):
            print(json.dumps({"id": row["id"], "tier": row["tier"], "title": row["title"], "branch": row["branch"]}))
            return
    print("EMPTY")

def cmd_context(a):
    con = db()
    row = con.execute("SELECT * FROM tasks WHERE id=?", (a.id,)).fetchone()
    if not row:
        sys.exit(f"no task {a.id}")
    print(f"# TASK {row['id']} [{row['tier']}] {row['title']}\n\n## Brief\n{row['brief']}\n")
    if row["branch"]:
        print(f"## Existing branch / PR\nBranch: {row['branch']}\nPR: {row['pr_url'] or '(not opened yet)'}\n"
              f"This task already has work in progress on this branch — reuse it, do not create a new branch or a new PR.\n")
    if row["status"] == "queued" and row["attempts"] > 0 and row["handover"]:
        print(f"## Review feedback from the previous attempt (address this)\n{row['handover']}\n")
    ids = [d.strip() for d in (row["depends_on"] or "").split(",") if d.strip()]
    if ids:
        print("## Notes from tasks this depends on")
        q = ",".join("?" * len(ids))
        for dep in con.execute(f"SELECT id,title,handover,commit_sha FROM tasks WHERE id IN ({q})", ids):
            print(f"- task {dep['id']} ({dep['title']}) commit={dep['commit_sha'] or '-'}: {dep['handover'] or '(no notes)'}")
        print()
    print("## Recent commits")
    try:
        print(subprocess.run(["git", "log", "--oneline", "-5"], capture_output=True, text=True, cwd=os.path.dirname(HERE)).stdout)
    except Exception as e:
        print("(git unavailable:", e, ")")

def set_status(task_id, status, **fields):
    con = db()
    sets, vals = ["status=?", "updated_at=?"], [status, now()]
    for k, v in fields.items():
        sets.append(f"{k}=?"); vals.append(v)
    vals.append(task_id)
    con.execute(f"UPDATE tasks SET {', '.join(sets)} WHERE id=?", vals)
    con.commit()

def cmd_start(a):
    set_status(a.id, "in_progress")
    print(f"OK task {a.id} in_progress")

def cmd_pr(a):
    set_status(a.id, "pr_open", branch=a.branch, pr_url=a.url)
    print(f"OK task {a.id} pr_open branch={a.branch} url={a.url}")

def cmd_approve(a):
    set_status(a.id, "approved", handover=(a.notes or "")[:HANDOVER_MAX])
    print(f"OK task {a.id} approved, ready to merge")

def cmd_revise(a):
    con = db()
    row = con.execute("SELECT attempts FROM tasks WHERE id=?", (a.id,)).fetchone()
    set_status(a.id, "queued", handover=a.reason[:HANDOVER_MAX],
               attempts=(row["attempts"] + 1) if row else 1)
    print(f"OK task {a.id} sent back for revision (branch/PR kept)")

def cmd_done(a):
    set_status(a.id, "done", handover=a.handover[:HANDOVER_MAX], commit_sha=a.commit or "")
    print(f"OK task {a.id} done")

def cmd_block(a):
    con = db()
    row = con.execute("SELECT tier, attempts FROM tasks WHERE id=?", (a.id,)).fetchone()
    if row and row["attempts"] == 0 and row["tier"] in ESCALATE:
        con.execute("UPDATE tasks SET status='queued', tier=?, attempts=1, handover=?, updated_at=? WHERE id=?",
                    (ESCALATE[row["tier"]], ("prev attempt failed: " + a.reason)[:HANDOVER_MAX], now(), a.id))
        con.commit()
        print(f"OK task {a.id} escalated to {ESCALATE[row['tier']]} and requeued")
    else:
        set_status(a.id, "blocked", handover=a.reason[:HANDOVER_MAX],
                   attempts=(row["attempts"] + 1) if row else 1)
        print(f"OK task {a.id} blocked")

def cmd_reap(a):
    """Idempotent safety net for runner.sh: an executor/review/merge session is
    contracted to end by calling one of pr/approve/revise/done/block itself. If
    it exits (0 or not) without doing so — ran out of turns mid-work, crashed
    silently, forgot — the task is left dangling at in_progress forever and
    `next` has no way to notice. Call this unconditionally after every session;
    it no-ops if the session already recorded a real outcome, and otherwise
    routes through the same block()/escalation ladder so a reaped task is
    never silently lost."""
    con = db()
    row = con.execute("SELECT status FROM tasks WHERE id=?", (a.id,)).fetchone()
    if not row:
        sys.exit(f"no task {a.id}")
    if row["status"] != "in_progress":
        print(f"OK task {a.id} status={row['status']}, nothing to reap")
        return
    cmd_block(argparse.Namespace(id=a.id, reason=a.reason))

def cmd_status(_):
    con = db()
    for r in con.execute("SELECT status, COUNT(*) n FROM tasks GROUP BY status"):
        print(f"{r['status']}: {r['n']}")
    for r in con.execute("SELECT id,title,handover FROM tasks WHERE status='blocked'"):
        print(f"  BLOCKED {r['id']}: {r['title']} — {r['handover']}")
    for r in con.execute("SELECT id,title,pr_url FROM tasks WHERE status='pr_open'"):
        print(f"  PR_OPEN {r['id']}: {r['title']} — {r['pr_url']}")
    for r in con.execute("SELECT id,title,pr_url FROM tasks WHERE status='approved'"):
        print(f"  APPROVED {r['id']}: {r['title']} — {r['pr_url']}")

def cmd_export(_):
    con = db()
    out = ["# Loop status", "", f"_updated {now()}_", "", "| id | tier | status | title | branch/PR | notes |", "|---|---|---|---|---|---|"]
    for r in con.execute("SELECT * FROM tasks ORDER BY id"):
        branch_pr = r["pr_url"] or r["branch"] or ""
        out.append(f"| {r['id']} | {r['tier']} | {r['status']} | {r['title']} | {branch_pr} | {(r['handover'] or '').replace(chr(10), ' ')} |")
    path = os.path.join(HERE, "LOOP_STATUS.md")
    open(path, "w").write("\n".join(out) + "\n")
    print("OK wrote", path)

def main():
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("init")
    a = sub.add_parser("add"); a.add_argument("title"); a.add_argument("--tier", required=True, choices=["trivial", "standard", "complex", "architect"]); a.add_argument("--brief", required=True); a.add_argument("--deps", default="")
    sub.add_parser("next")
    c = sub.add_parser("context"); c.add_argument("id", type=int)
    s = sub.add_parser("start"); s.add_argument("id", type=int)
    pr = sub.add_parser("pr"); pr.add_argument("id", type=int); pr.add_argument("--branch", required=True); pr.add_argument("--url", required=True)
    ap = sub.add_parser("approve"); ap.add_argument("id", type=int); ap.add_argument("--notes", default="")
    rv = sub.add_parser("revise"); rv.add_argument("id", type=int); rv.add_argument("--reason", required=True)
    d = sub.add_parser("done"); d.add_argument("id", type=int); d.add_argument("--handover", required=True); d.add_argument("--commit", default="")
    b = sub.add_parser("block"); b.add_argument("id", type=int); b.add_argument("--reason", required=True)
    rp = sub.add_parser("reap"); rp.add_argument("id", type=int); rp.add_argument("--reason", required=True)
    sub.add_parser("status")
    sub.add_parser("export")
    args = p.parse_args()
    globals()["cmd_" + args.cmd](args)

if __name__ == "__main__":
    main()
