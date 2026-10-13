#!/usr/bin/env python3
"""Synthetic fixture builder + expectations for verify-evidence.sh and
extract-evidence.sh.

Builds evidence packages — and for the E2E fixtures, fake RUN directories
fed through extract-evidence.sh — WITHOUT running any target. Each
fixture declares expected EVIDENCE_INTEGRITY / RUN_VALIDITY /
OBSERVATION / ELIGIBLE_FOR_COMPARISON outcomes.

Run:  python3 test-fixtures.py [scratch_dir]
"""
import hashlib, json, os, shutil, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
VERIFY = os.path.join(HERE, "verify-evidence.sh")
EXTRACT = os.path.join(HERE, "extract-evidence.sh")

CANARY_CLAUDE_MS = 1791820000000
CANARY_CODEX_S = 1791820000

def manifest(run_id="fixture", history="canary", ready=True, early=False,
             remain=0, launch=1791820000.0):
    return {
        "run_id": run_id, "history_mode": history,
        "target": {"computed_sha256": "0" * 64, "expected_sha256": "0" * 64,
                   "identity": "match",
                   "workbench_js": {"computed_sha256": "1" * 64,
                                    "expected_sha256": "1" * 64,
                                    "identity": "match"}},
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
                   "requested_duration_s": 240, "total_runtime_s": 240.0,
                   "observed_window_s": 235.0},
        "readiness": {"workbench_window_logdir_and_renderer_log_and_state_db": ready},
        "process": {"early_exit": early, "cancelled": False, "launch_pid": 1,
                    "post_termination_remaining_processes": remain},
        "interventions": {"disable_crash_reporter": True},
    }

CLAUDE_INPUT = {"display": "REA_R33_CANARY_CLAUDE synthetic entry fixture",
                "timestamp": CANARY_CLAUDE_MS, "sessionId": "fixture-canary-claude"}
CODEX_INPUT = {"session_id": "fixture-canary-codex", "ts": CANARY_CODEX_S,
               "text": "REA_R33_CANARY_CODEX synthetic entry fixture"}

def utf16(s): return len(s.encode("utf-16-le")) // 2

def claude_event(ts=None, message="ex_hs2", tool="ac", ts_event=1791820024.1):
    return {"timestamp": ts_event, "category": "event", "message": message,
            "data": {"tool": tool, "ts": CANARY_CLAUDE_MS if ts is None else ts,
                     "sessionId": "fixture-canary-claude",
                     "n": utf16(CLAUDE_INPUT["display"]), "msgCount": 1}}

def codex_event(ts=None, ts_event=1791820025.0):
    return {"timestamp": ts_event, "category": "event", "message": "ex_hs2",
            "data": {"tool": "cx", "ts": CANARY_CODEX_S * 1000 if ts is None else ts,
                     "sessionId": "fixture-canary-codex",
                     "n": utf16(CODEX_INPUT["text"])}}

def write_pkg(root, m, breadcrumbs, sqlite_lines, inputs=True,
              skip_files=(), extra_raw_dedup=None, hash_only=(),
              input_override=None):
    os.makedirs(os.path.join(root, "inputs"), exist_ok=True)
    with open(os.path.join(root, "run-manifest.json"), "w") as f:
        json.dump(m, f)
    if inputs:
        cli = CLAUDE_INPUT if input_override is None else input_override.get("claude", CLAUDE_INPUT)
        cxi = CODEX_INPUT if input_override is None else input_override.get("codex", CODEX_INPUT)
        with open(os.path.join(root, "inputs/claude-history.jsonl"), "w") as f:
            f.write(json.dumps(cli) + "\n")
        with open(os.path.join(root, "inputs/codex-history.jsonl"), "w") as f:
            f.write(json.dumps(cxi) + "\n")
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
                   "files_with_errors": [], "unparsed_candidates": [],
                   "missing_dir": False}, f)
    # hashes.txt over package files; hash_only restricts coverage to the
    # named files (a partial-coverage counterexample).
    entries = []
    for dp, _, fns in os.walk(root):
        for fn in fns:
            if fn == "hashes.txt":
                continue
            p = os.path.join(dp, fn)
            rel = os.path.relpath(p, root)
            if hash_only and rel not in hash_only:
                continue
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
def fix(name, builder, ei, rv, obs, elig):
    FIXTURES.append((name, builder, ei, rv, obs, elig))

# 1. Correct positive: both canaries present, codex ts in milliseconds.
fix("F1-positive-correct-ms",
    lambda r: write_pkg(r, manifest(), [bline(claude_event()), bline(codex_event())], bm_lines()),
    "PASS", "VALID", "OBSERVED", "YES")

# 2. Counterexample: codex event exists with our sessionId but ts in
#    SECONDS — that is FIELD_MISMATCH, not "not observed".
fix("F2-codex-seconds-field-mismatch",
    lambda r: write_pkg(r, manifest(),
        [bline(claude_event()), bline(codex_event(ts=CANARY_CODEX_S))], bm_lines()),
    "PASS", "VALID", "FIELD_MISMATCH", "YES")

# 3. Counterexample: hashes.txt entirely absent — integrity must FAIL.
fix("F3-missing-hashes",
    lambda r: write_pkg(r, manifest(), [bline(claude_event()), bline(codex_event())],
                        bm_lines(), skip_files=("hashes.txt",)),
    "FAIL", "VALID", "NOT_ASSESSED", "NO")

# 4. Counterexample: dedup has same line count as raw's unique bodies but
#    DIFFERENT content — subset check must fail.
fix("F4-fake-dedup-different-content",
    lambda r: write_pkg(r, manifest(),
        [bline(claude_event()), bline(claude_event()), bline(codex_event())],
        bm_lines(),
        extra_raw_dedup=['{"fake":"record"}', '{"another":"fake"}']),
    "FAIL", "VALID", "NOT_ASSESSED", "NO")

# 5. JSON field order / whitespace variation must still parse.
def f5(r):
    ev = claude_event()
    reordered = {"data": ev["data"], "message": "ex_hs2",
                 "category": "event", "timestamp": ev["timestamp"]}
    lines = ['log/x.log:1:0: ' + json.dumps(reordered, separators=(', ', ' : ')) + "\n",
             bline(codex_event())]
    return write_pkg(r, manifest(), lines, bm_lines())
fix("F5-field-order-whitespace", f5, "PASS", "VALID", "OBSERVED", "YES")

# 6. Corrupt breadcrumb body → integrity FAIL (parse cannot fake zero events).
def f6(r):
    return write_pkg(r, manifest(),
        ["log/x.log:1:0: {broken json\n", bline(claude_event()), bline(codex_event())],
        bm_lines())
fix("F6-corrupt-breadcrumb", f6, "FAIL", "VALID", "NOT_ASSESSED", "NO")

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
fix("F7-non-bmp-utf16-length", f7, "PASS", "VALID", "OBSERVED", "YES")

# 8. Valid run, zero events → clean NOT_OBSERVED (integrity still PASS,
#    eligible for matrix comparison).
fix("F8-valid-negative",
    lambda r: write_pkg(r, manifest(), [], ["externalCliAnalytics.lastTimestamp.claude|0"]),
    "PASS", "VALID", "NOT_OBSERVED_WITHIN_WINDOW", "YES")

# 9. Early exit → RUN_VALIDITY INVALID, observation not assessed.
fix("F9-early-exit-invalid",
    lambda r: write_pkg(r, manifest(early=True), [bline(claude_event()), bline(codex_event())],
                        bm_lines()),
    "PASS", "INVALID", "NOT_ASSESSED", "NO")

# 10. Not-ready run with a real positive → QUALIFIED validity, observation
#     retained as a limited fact, but NOT eligible for comparison.
fix("F10-not-ready-qualified-positive",
    lambda r: write_pkg(r, manifest(ready=False), [bline(claude_event()), bline(codex_event())],
                        bm_lines()),
    "PASS", "QUALIFIED", "OBSERVED", "NO")

# 11. Missing packaged input → integrity FAIL, no downgrade to n-int-check.
fix("F11-missing-packaged-input",
    lambda r: write_pkg(r, manifest(), [bline(claude_event()), bline(codex_event())],
                        bm_lines(), inputs=False),
    "FAIL", "VALID", "NOT_ASSESSED", "NO")

# 12. Partial hash coverage: manifest lists only one input — must FAIL
#     completeness even though the listed entry is valid.
fix("F12-partial-hash-coverage",
    lambda r: write_pkg(r, manifest(), [bline(claude_event()), bline(codex_event())],
                        bm_lines(), hash_only=("inputs/claude-history.jsonl",)),
    "FAIL", "VALID", "NOT_ASSESSED", "NO")

# 13. Wrong event name with our sessionId: exists, but is not an ex_hs2
#     claim — FIELD_MISMATCH, never OBSERVED.
fix("F13-wrong-event-name",
    lambda r: write_pkg(r, manifest(),
        [bline(claude_event(message="env_ac")), bline(codex_event())], bm_lines()),
    "PASS", "VALID", "FIELD_MISMATCH", "YES")

# 14. Event record timestamped BEFORE launch: cannot be attributed to
#     this run — FIELD_MISMATCH, not observed.
fix("F14-event-before-launch",
    lambda r: write_pkg(r, manifest(),
        [bline(claude_event(ts_event=1791819990.0)), bline(codex_event())], bm_lines()),
    "PASS", "VALID", "FIELD_MISMATCH", "YES")

# 15. Manifest claims a sessionId that the packaged input does not carry
#     → integrity FAIL (manifest-input binding broken).
def f15(r):
    m = manifest()
    m["synthetic_inputs"]["claude"]["sessionId"] = "manifest-claims-different"
    return write_pkg(r, m, [bline(claude_event()), bline(codex_event())], bm_lines())
fix("F15-manifest-input-mismatch", f15, "FAIL", "VALID", "NOT_ASSESSED", "NO")

# 16. Not-ready run with ZERO events: not a valid negative — observation
#     reported but NOT eligible for comparison.
fix("F16-not-ready-zero-events",
    lambda r: write_pkg(r, manifest(ready=False), [],
                        ["externalCliAnalytics.lastTimestamp.claude|0"]),
    "PASS", "QUALIFIED", "NOT_OBSERVED_WITHIN_WINDOW", "NO")

# 17. Cleanup left processes behind: run ended but evidence source may
#     still be live — VALID validity, ineligible.
fix("F17-cleanup-incomplete",
    lambda r: write_pkg(r, manifest(remain=2), [bline(claude_event()), bline(codex_event())],
                        bm_lines()),
    "PASS", "VALID", "OBSERVED", "NO")

# 18. Real R0: history_mode=none with genuinely EMPTY input files — a
#     valid "no records" state, not corrupt input.
def f18(r):
    m = manifest(history="none")
    m["synthetic_inputs"]["claude"]["sessionId"] = ""
    m["synthetic_inputs"]["codex"]["session_id"] = ""
    root = write_pkg(r, m, [], ["externalCliAnalytics.lastTimestamp.claude|0"],
                     input_override={"claude": None, "codex": None})
    for f in ("inputs/claude-history.jsonl", "inputs/codex-history.jsonl"):
        with open(os.path.join(root, f), "w") as fh:
            fh.write("")
    # inputs changed after hashing — re-hash whole package
    entries = []
    for dp, _, fns in os.walk(root):
        for fn in fns:
            if fn != "hashes.txt":
                p = os.path.join(dp, fn)
                entries.append((hashlib.sha256(open(p, "rb").read()).hexdigest(),
                                os.path.relpath(p, root)))
    with open(os.path.join(root, "hashes.txt"), "w") as fh:
        fh.writelines(f"{h}  {rel}\n" for h, rel in sorted(entries))
    return root
fix("F18-r0-empty-history-inputs", f18, "PASS", "VALID",
    "NOT_OBSERVED_WITHIN_WINDOW", "YES")

# 19. Inputs exist but are NOT listed in hashes.txt — coverage gap must
#     fail integrity (existence is not coverage).
fix("F19-inputs-not-hash-covered",
    lambda r: write_pkg(r, manifest(),
        [bline(claude_event()), bline(codex_event())], bm_lines(),
        hash_only=("run-manifest.json", "breadcrumbs-raw.txt",
                   "breadcrumbs-deduped.txt", "state-vscdb-scoped.txt",
                   "extract-report.json")),
    "FAIL", "VALID", "NOT_ASSESSED", "NO")

# 20. Cancelled run that was once ready and cleaned up → limited run,
#     positive retained, never eligible.
fix("F20-cancelled-positive",
    lambda r: write_pkg(r, {**manifest(), "process":
                            {**manifest()["process"], "cancelled": True}},
        [bline(claude_event()), bline(codex_event())], bm_lines()),
    "PASS", "VALID", "OBSERVED", "NO")

# 21. Positive records but launch epoch missing → window unverifiable:
#     partial observation retained, comparison refused, no crash.
def f21(r):
    m = manifest()
    m["phases"]["launch_epoch_s"] = None
    return write_pkg(r, m, [bline(claude_event()), bline(codex_event())], bm_lines())
fix("F21-missing-launch-epoch", f21, "PASS", "VALID", "OBSERVED_PARTIAL", "NO")

# 22. ready_epoch missing while readiness claims reached → ineligible.
def f22(r):
    m = manifest()
    m["phases"]["ready_epoch_s"] = None
    return write_pkg(r, m, [bline(claude_event()), bline(codex_event())], bm_lines())
fix("F22-missing-ready-epoch", f22, "PASS", "VALID", "OBSERVED", "NO")

# ---------- E2E: raw log -> extract-evidence -> package -> verify ----------

def build_run_dir(root, log_lines, m=None, with_inputs=True):
    """Build a fake frozen RUN_DIR that extract-evidence.sh can read."""
    m = m or manifest()
    rd = os.path.join(root, "rundir")
    fh = os.path.join(rd, "home")
    logd = os.path.join(fh, "cursor-data", "logs", "2026T00", "window1_wb1")
    os.makedirs(logd)
    os.makedirs(os.path.join(fh, ".claude"))
    os.makedirs(os.path.join(fh, ".codex"))
    os.makedirs(os.path.join(fh, "cursor-data", "User", "globalStorage"))
    with open(os.path.join(rd, "run-manifest.json"), "w") as f:
        json.dump(m, f)
    with open(os.path.join(logd, "cursor-sentry-events.log"), "w") as f:
        f.writelines(log_lines)
    # real sqlite bookmark rows so the full bookmark path is exercised
    import sqlite3
    db = os.path.join(fh, "cursor-data", "User", "globalStorage", "state.vscdb")
    con = sqlite3.connect(db)
    con.execute("CREATE TABLE ItemTable (key TEXT PRIMARY KEY, value TEXT)")
    con.executemany("INSERT INTO ItemTable VALUES (?,?)", [
        ("externalCliAnalytics.lastTimestamp.claude", str(CANARY_CLAUDE_MS)),
        ("externalCliAnalytics.lastTimestamp.codex", str(CANARY_CODEX_S * 1000)),
    ])
    con.commit(); con.close()
    with open(os.path.join(fh, ".claude", "history.jsonl"), "w") as f:
        f.write(json.dumps(CLAUDE_INPUT) + "\n" if with_inputs else "")
    with open(os.path.join(fh, ".codex", "history.jsonl"), "w") as f:
        f.write(json.dumps(CODEX_INPUT) + "\n" if with_inputs else "")
    with open(os.path.join(rd, "inputs-hashes.txt"), "w") as f:
        f.write("deadbeef  .claude/history.jsonl\n")
    return rd

def e2e(root, log_lines, m=None, with_inputs=True):
    rd = build_run_dir(root, log_lines, m=m, with_inputs=with_inputs)
    out = os.path.join(root, "pkg")
    p = subprocess.run(["bash", EXTRACT, "--run", rd, "--out", out],
                       capture_output=True, text=True)
    if p.returncode != 0:
        raise RuntimeError(f"extractor failed: {p.stderr}")
    return out

def rawline(rec):
    return json.dumps(rec, separators=(",", ":")) + "\n"

# E1: normal one-record-per-line log → extracted, OBSERVED.
fix("E1-e2e-normal",
    lambda r: e2e(r, [rawline(claude_event()), rawline(codex_event())]),
    "PASS", "VALID", "OBSERVED", "YES")

# E2: corrupt JSON line carrying the ex_hs2 marker → extractor records an
#     unparsed candidate → integrity FAIL (cannot fake zero events).
fix("E2-e2e-corrupt-marker-line",
    lambda r: e2e(r, ['{"category":"event","message":"ex_hs2","data":{BROKEN\n',
                      rawline(codex_event())]),
    "FAIL", "VALID", "NOT_ASSESSED", "NO")

# E3: JSON string containing braces/backslashes — scanner must not break
#     the object boundary → extracted normally.
def e3(r):
    ev = claude_event()
    ev["data"]["extra"] = 'brace } inside { string "with" \\ escapes }'
    return e2e(r, [rawline(ev), rawline(codex_event())])
fix("E3-e2e-braces-in-string", e3, "PASS", "VALID", "OBSERVED", "YES")

# E4: breadcrumb nested inside a wrapper object — real-logs coverage probe;
#     extractor descends one level deep, finds the event.
def e4(r):
    wrapped = {"level": "info", "rec": claude_event()}
    return e2e(r, [rawline(wrapped), rawline(codex_event())])
fix("E4-e2e-wrapped-record", e4, "PASS", "VALID", "OBSERVED", "YES")

# E5: truncated (unbalanced) record with the marker → unparsed candidate
#     → integrity FAIL.
fix("E5-e2e-truncated-marker",
    lambda r: e2e(r, ['{"category":"event","message":"ex_hs2","data":{"tool":"cx","sessionId":"fixture-canary-codex","ts":1791820',
                      rawline(claude_event())]),
    "FAIL", "VALID", "NOT_ASSESSED", "NO")

def run():
    scratch = sys.argv[1] if len(sys.argv) > 1 else tempfile.mkdtemp(prefix="rea-fixtures-")
    os.makedirs(scratch, exist_ok=True)
    failures = []
    for name, builder, ei, rv, obs, elig in FIXTURES:
        root = os.path.join(scratch, name)
        if os.path.exists(root):
            shutil.rmtree(root)
        try:
            pkg = builder(root)
        except Exception as e:
            print(f"FAIL {name}: builder raised {e}")
            failures.append(name)
            continue
        p = subprocess.run(["bash", VERIFY, "--evidence", pkg],
                           capture_output=True, text=True)
        got = {}
        for l in p.stdout.splitlines():
            if l.startswith(("EVIDENCE_INTEGRITY", "RUN_VALIDITY",
                             "OBSERVATION", "ELIGIBLE_FOR_COMPARISON")):
                k, _, v = l.partition("=")
                got[k.strip()] = v.strip().split()[0]
        ok = (got.get("EVIDENCE_INTEGRITY") == ei and
              got.get("RUN_VALIDITY") == rv and
              got.get("OBSERVATION") == obs and
              got.get("ELIGIBLE_FOR_COMPARISON") == elig)
        status = "PASS" if ok else "FAIL"
        print(f"{status} {name}: want({ei},{rv},{obs},{elig}) got({got.get('EVIDENCE_INTEGRITY')},{got.get('RUN_VALIDITY')},{got.get('OBSERVATION')},{got.get('ELIGIBLE_FOR_COMPARISON')})")
        if not ok:
            failures.append(name)
            print(p.stdout)
            print(p.stderr)
    print(f"\n{len(FIXTURES) - len(failures)}/{len(FIXTURES)} fixtures matched expectations")
    sys.exit(1 if failures else 0)

if __name__ == "__main__":
    run()
