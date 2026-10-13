#!/usr/bin/env python3
"""Synthetic fixture builder + expectations for verify-evidence.sh.

Builds evidence packages under a scratch dir WITHOUT running any target.
Each fixture declares expected EVIDENCE_INTEGRITY / RUN_VALIDITY /
OBSERVATION outcomes. Run:  python3 test-fixtures.py [scratch_dir]
"""
import hashlib, json, os, shutil, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
VERIFY = os.path.join(HERE, "verify-evidence.sh")

CANARY_CLAUDE_MS = 1791820000000
CANARY_CODEX_S = 1791820000

def manifest(run_id="fixture", history="canary", ready=True, early=False,
             remain=0, launch=1791820000.0):
    return {
        "run_id": run_id, "history_mode": history,
        "target": {"computed_sha256": "0" * 64, "identity": "match"},
        "runner": {"script_sha256": "0" * 64},
        "synthetic_inputs": {
            "claude": {"packaged_file": "inputs/claude-history.jsonl",
                       "sessionId": f"{run_id}-canary-claude",
                       "timestamp_ms": CANARY_CLAUDE_MS},
            "codex": {"packaged_file": "inputs/codex-history.jsonl",
                      "session_id": f"{run_id}-canary-codex",
                      "ts_seconds": CANARY_CODEX_S},
        },
        "phases": {"probe_epoch_s": launch - 1, "launch_epoch_s": launch,
                   "ready_epoch_s": launch + 5, "obs_end_epoch_s": launch + 240,
                   "requested_duration_s": 240},
        "readiness": {"workbench_window_logdir_and_renderer_log_and_state_db": ready},
        "process": {"early_exit": early, "launch_pid": 1,
                    "post_termination_remaining_processes": remain},
        "interventions": {"disable_crash_reporter": True},
    }

CLAUDE_INPUT = {"display": f"REA_R33_CANARY_CLAUDE synthetic entry fixture",
                "timestamp": CANARY_CLAUDE_MS, "sessionId": "fixture-canary-claude"}
CODEX_INPUT = {"session_id": "fixture-canary-codex", "ts": CANARY_CODEX_S,
               "text": "REA_R33_CANARY_CODEX synthetic entry fixture"}

def utf16(s): return len(s.encode("utf-16-le")) // 2

def claude_event():
    return {"timestamp": 1791820024.1, "category": "event", "message": "ex_hs2",
            "data": {"tool": "ac", "ts": CANARY_CLAUDE_MS,
                     "sessionId": "fixture-canary-claude",
                     "n": utf16(CLAUDE_INPUT["display"]), "msgCount": 1}}

def codex_event(ts=None):
    return {"timestamp": 1791820025.0, "category": "event", "message": "ex_hs2",
            "data": {"tool": "cx", "ts": CANARY_CODEX_S * 1000 if ts is None else ts,
                     "sessionId": "fixture-canary-codex",
                     "n": utf16(CODEX_INPUT["text"])}}

def write_pkg(root, m, breadcrumbs, sqlite_lines, inputs=True,
              skip_files=(), extra_raw_dedup=None):
    os.makedirs(os.path.join(root, "inputs"), exist_ok=True)
    with open(os.path.join(root, "run-manifest.json"), "w") as f:
        json.dump(m, f)
    if inputs:
        with open(os.path.join(root, "inputs/claude-history.jsonl"), "w") as f:
            f.write(json.dumps(CLAUDE_INPUT) + "\n")
        with open(os.path.join(root, "inputs/codex-history.jsonl"), "w") as f:
            f.write(json.dumps(CODEX_INPUT) + "\n")
    with open(os.path.join(root, "breadcrumbs-raw.txt"), "w") as f:
        f.writelines(breadcrumbs)
    dedup = extra_raw_dedup
    if dedup is None:
        bodies = [l.split(": ", 1)[-1].rstrip("\n") for l in breadcrumbs]
        dedup = sorted(set(bodies))
    with open(os.path.join(root, "breadcrumbs-deduped.txt"), "w") as f:
        f.writelines(d + "\n" for d in dedup)
    with open(os.path.join(root, "state-vscdb-scoped.txt"), "w") as f:
        f.writelines(l + "\n" for l in sqlite_lines)
    with open(os.path.join(root, "extract-report.json"), "w") as f:
        json.dump({"files_scanned": 1, "bytes_scanned": 1000,
                   "records_matched": len(breadcrumbs),
                   "files_with_errors": [], "missing_dir": False}, f)
    # hashes.txt last, over remaining files
    entries = []
    for dp, _, fns in os.walk(root):
        for fn in fns:
            if fn == "hashes.txt":
                continue
            p = os.path.join(dp, fn)
            rel = os.path.relpath(p, root)
            entries.append((hashlib.sha256(open(p, "rb").read()).hexdigest(), rel))
    with open(os.path.join(root, "hashes.txt"), "w") as f:
        for h, rel in sorted(entries):
            f.write(f"{h}  {rel}\n")
    # skip_files applied AFTER hashing so a fixture can remove the manifest
    # itself (leaving stale references would also be a valid failure mode).
    for fn in skip_files:
        p = os.path.join(root, fn)
        if os.path.exists(p):
            os.remove(p) if os.path.isfile(p) else shutil.rmtree(p)
    return root

def bline(rec):
    return f"log/cursor-sentry-events.log:1:0: {json.dumps(rec, separators=(',', ':'))}\n"

def bm_lines():
    return [f"externalCliAnalytics.lastTimestamp.claude|{CANARY_CLAUDE_MS}",
            f"externalCliAnalytics.lastTimestamp.codex|{CANARY_CODEX_S * 1000}"]

FIXTURES = []
def fix(name, builder, ei, rv, obs):
    FIXTURES.append((name, builder, ei, rv, obs))

# 1. Correct positive: both canaries present, codex ts in milliseconds.
fix("F1-positive-correct-ms",
    lambda r: write_pkg(r, manifest(), [bline(claude_event()), bline(codex_event())], bm_lines()),
    "PASS", "VALID", "OBSERVED")

# 2. Counterexample: codex event ts wrongly in SECONDS — must MISS the
#    exact ms correspondence check.
fix("F2-codex-seconds-rejected",
    lambda r: write_pkg(r, manifest(),
        [bline(claude_event()), bline(codex_event(ts=CANARY_CODEX_S))], bm_lines()),
    "PASS", "VALID", "NOT_OBSERVED_WITHIN_WINDOW")

# 3. Counterexample: hashes.txt entirely absent — integrity must FAIL.
fix("F3-missing-hashes",
    lambda r: write_pkg(r, manifest(), [bline(claude_event()), bline(codex_event())],
                        bm_lines(), skip_files=("hashes.txt",)),
    "FAIL", "VALID", "NOT_ASSESSED")

# 4. Counterexample: dedup has same line count as raw's unique bodies but
#    DIFFERENT content — subset check must fail.
fix("F4-fake-dedup-different-content",
    lambda r: write_pkg(r, manifest(),
        [bline(claude_event()), bline(claude_event()), bline(codex_event())],
        bm_lines(),
        extra_raw_dedup=['{"fake":"record"}', '{"another":"fake"}']),
    "FAIL", "VALID", "NOT_ASSESSED")

# 5. JSON field order / whitespace variation must still parse.
def f5(r):
    ev = claude_event()
    # keys reordered + whitespace inside the record
    reordered = {"data": ev["data"], "message": "ex_hs2",
                 "category": "event", "timestamp": ev["timestamp"]}
    lines = ['log/x.log:1:0: ' + json.dumps(reordered, separators=(', ', ' : ')) + "\n",
             bline(codex_event())]
    return write_pkg(r, manifest(), lines, bm_lines())
fix("F5-field-order-whitespace", f5, "PASS", "VALID", "OBSERVED")

# 6. Corrupt breadcrumb body → integrity FAIL (parse cannot fake zero events).
def f6(r):
    return write_pkg(r, manifest(),
        ["log/x.log:1:0: {broken json\n", bline(claude_event()), bline(codex_event())],
        bm_lines())
fix("F6-corrupt-breadcrumb", f6, "FAIL", "VALID", "NOT_ASSESSED")

# 7. Non-BMP char in display text: n must be UTF-16 length (emoji = 2 units).
def f7(r):
    text = "REA_R33_CANARY_CLAUDE emoji \U0001f600 end"
    global CLAUDE_INPUT
    old = CLAUDE_INPUT["display"]
    CLAUDE_INPUT = {**CLAUDE_INPUT, "display": text}
    ev = claude_event()
    ev["data"]["n"] = utf16(text)
    out = write_pkg(r, manifest(), [bline(ev), bline(codex_event())], bm_lines())
    CLAUDE_INPUT = {**CLAUDE_INPUT, "display": old}
    return out
fix("F7-non-bmp-utf16-length", f7, "PASS", "VALID", "OBSERVED")

# 8. Valid run, zero events → clean NOT_OBSERVED (integrity still PASS).
fix("F8-valid-negative",
    lambda r: write_pkg(r, manifest(), [], ["externalCliAnalytics.lastTimestamp.claude|0"]),
    "PASS", "VALID", "NOT_OBSERVED_WITHIN_WINDOW")

# 9. Early exit → RUN_VALIDITY INVALID, observation not assessed.
fix("F9-early-exit-invalid",
    lambda r: write_pkg(r, manifest(early=True), [bline(claude_event()), bline(codex_event())],
                        bm_lines()),
    "PASS", "INVALID", "NOT_ASSESSED")

# 10. Not-ready run → QUALIFIED validity, observation still assessed.
fix("F10-not-ready-qualified",
    lambda r: write_pkg(r, manifest(ready=False), [bline(claude_event()), bline(codex_event())],
                        bm_lines()),
    "PASS", "QUALIFIED", "OBSERVED")

# 11. Missing packaged input → integrity FAIL, no downgrade to n-int-check.
fix("F11-missing-packaged-input",
    lambda r: write_pkg(r, manifest(), [bline(claude_event()), bline(codex_event())],
                        bm_lines(), inputs=False),
    "FAIL", "VALID", "NOT_ASSESSED")

def run():
    scratch = sys.argv[1] if len(sys.argv) > 1 else tempfile.mkdtemp(prefix="rea-fixtures-")
    os.makedirs(scratch, exist_ok=True)
    failures = []
    for name, builder, ei, rv, obs in FIXTURES:
        root = os.path.join(scratch, name)
        if os.path.exists(root):
            shutil.rmtree(root)
        builder(root)
        p = subprocess.run(["bash", VERIFY, "--evidence", root],
                           capture_output=True, text=True)
        tail = [l for l in p.stdout.splitlines()
                if l.startswith(("EVIDENCE_INTEGRITY", "RUN_VALIDITY", "OBSERVATION"))]
        got = {}
        for l in tail:
            k, _, v = l.partition("=")
            got[k.strip()] = v.strip().split()[0]
        ok = (got.get("EVIDENCE_INTEGRITY") == ei and
              got.get("RUN_VALIDITY") == rv and
              got.get("OBSERVATION") == obs)
        status = "PASS" if ok else "FAIL"
        print(f"{status} {name}: want({ei},{rv},{obs}) got({got.get('EVIDENCE_INTEGRITY')},{got.get('RUN_VALIDITY')},{got.get('OBSERVATION')})")
        if not ok:
            failures.append(name)
            print(p.stdout)
    print(f"\n{len(FIXTURES) - len(failures)}/{len(FIXTURES)} fixtures matched expectations")
    sys.exit(1 if failures else 0)

if __name__ == "__main__":
    run()
