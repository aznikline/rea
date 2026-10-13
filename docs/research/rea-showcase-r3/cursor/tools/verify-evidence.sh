#!/bin/bash
# verify-evidence.sh — verify a packaged evidence directory.
#
# Does NOT launch the target. Emits three independent verdicts:
#   EVIDENCE_INTEGRITY — required files present, hashes recompute,
#                        inputs packaged, parse health acceptable.
#   RUN_VALIDITY       — run actually reached an observable state
#                        (readiness + no early exit + cleanup complete).
#   OBSERVATION        — whether canary fields propagated, reported as
#                        OBSERVED / NOT_OBSERVED_WITHIN_WINDOW /
#                        NOT_ASSESSED (when integrity or validity fails).
#
# A complete package from a valid run with no events is a legitimate
# NOT_OBSERVED result — integrity does not require a positive.
#
# Usage: verify-evidence.sh --evidence DIR

set -euo pipefail

EV=""
while [ $# -gt 0 ]; do
  case "$1" in --evidence) EV=$2; shift 2 ;; *) echo "unknown arg: $1" >&2; exit 2 ;; esac
done
[ -n "$EV" ] || { echo "usage: verify-evidence.sh --evidence DIR" >&2; exit 2; }

EV="$EV" python3 <<'PYEOF'
import hashlib, json, os, re, sys

ev = os.environ["EV"]

integrity_fails = []
validity_notes = []
obs_fails = []

def icheck(name, ok, detail=""):
    print(f"INTEGRITY {'PASS' if ok else 'FAIL'} {name} {detail}")
    if not ok: integrity_fails.append(name)
def vcheck(name, ok, detail=""):
    print(f"VALIDITY  {'PASS' if ok else 'WARN'} {name} {detail}")
    if not ok: validity_notes.append(name)
def ocheck(name, ok, detail=""):
    print(f"OBSERVE   {'PASS' if ok else 'MISS'} {name} {detail}")
    if not ok: obs_fails.append(name)

REQUIRED = ["run-manifest.json", "hashes.txt", "breadcrumbs-raw.txt",
            "breadcrumbs-deduped.txt", "state-vscdb-scoped.txt",
            "extract-report.json"]

# ---------- 1. EVIDENCE_INTEGRITY ----------
missing = [f for f in REQUIRED if not os.path.exists(os.path.join(ev, f))]
icheck("required files present", not missing, str(missing))

m = None
if os.path.exists(os.path.join(ev, "run-manifest.json")):
    try:
        m = json.load(open(os.path.join(ev, "run-manifest.json")))
    except ValueError as e:
        icheck("run-manifest parses", False, str(e))
else:
    icheck("run-manifest parses", False, "absent")

# hash manifest: EVERY entry must recompute; file absent is a failure,
# not a skip.
hpath = os.path.join(ev, "hashes.txt")
if os.path.exists(hpath):
    n_entries = 0
    for line in open(hpath):
        parts = line.rsplit(None, 1)
        if len(parts) != 2:
            icheck("hashes.txt line parses", False, line.strip()[:60]); continue
        want, p = parts[0], parts[1].strip()
        n_entries += 1
        path = p if os.path.isabs(p) else os.path.join(ev, p)
        if os.path.exists(path):
            got = hashlib.sha256(open(path, "rb").read()).hexdigest()
            icheck(f"hash {p}", got == want, got[:12])
        else:
            icheck(f"hash {p}", False, "referenced file missing")
    icheck("hashes.txt non-empty", n_entries > 0, f"{n_entries} entries")

# packaged inputs must exist inside the package — resolved via manifest
# `packaged_file`, with the extractor's conventional path as fallback
# for manifests written before the field existed.
if m:
    canon = m.get("synthetic_inputs", {})
    for side in ("claude", "codex"):
        rel = canon.get(side, {}).get("packaged_file") or f"inputs/{side}-history.jsonl"
        icheck(f"{side} packaged input exists",
               os.path.exists(os.path.join(ev, rel)), rel)

# extract-report parse health
report = {}
rpath = os.path.join(ev, "extract-report.json")
if os.path.exists(rpath):
    try:
        report = json.load(open(rpath))
        icheck("no extractor file errors", not report.get("files_with_errors"),
               str(report.get("files_with_errors"))[:80])
    except ValueError as e:
        icheck("extract-report parses", False, str(e))

# raw/deduped REAL set relationship — not just counts
raw_lines, ded_lines, raw_bodies = [], [], []
if os.path.exists(os.path.join(ev, "breadcrumbs-raw.txt")):
    raw_lines = open(os.path.join(ev, "breadcrumbs-raw.txt")).read().splitlines()
    raw_bodies = [l.split(": ", 1)[-1] for l in raw_lines if l.strip()]
if os.path.exists(os.path.join(ev, "breadcrumbs-deduped.txt")):
    ded_lines = open(os.path.join(ev, "breadcrumbs-deduped.txt")).read().splitlines()
raw_set, ded_set = set(raw_bodies), set(ded_lines)
icheck("dedup bodies are a true subset of raw bodies", ded_set <= raw_set,
       f"raw={len(raw_bodies)} dedup={len(ded_lines)} extra={len(ded_set - raw_set)}")
icheck("dedup equals unique raw bodies", ded_set == raw_set,
       f"|raw_set|={len(raw_set)} |dedup_set|={len(ded_set)}")
dups = len(raw_bodies) - len(raw_set)
print(f"INFO duplicate raw records: {dups} (raw count is NOT a distinct-event count)")

# ---------- 2. RUN_VALIDITY ----------
validity = "NOT_ASSESSED"
if m:
    readiness = m.get("readiness", {})
    proc = m.get("process", {})
    phases = m.get("phases", {})
    vcheck("readiness flag present", "workbench_window_logdir_and_renderer_log_and_state_db" in readiness)
    vcheck("workbench reached observable state",
           readiness.get("workbench_window_logdir_and_renderer_log_and_state_db") is True)
    vcheck("no early exit", proc.get("early_exit") is False)
    vcheck("cleanup complete",
           proc.get("post_termination_remaining_processes") in (0, "0"),
           str(proc.get("post_termination_remaining_processes")))
    vcheck("phase epochs recorded",
           all(phases.get(k) is not None for k in
               ("probe_epoch_s", "launch_epoch_s", "obs_end_epoch_s")))
    tgt = m.get("target", {})
    vcheck("target identity computed", bool(tgt.get("computed_sha256")),
           tgt.get("identity", "?"))
    if "script_sha256" not in m.get("runner", {}):
        vcheck("runner identity recorded", False, "older manifest without script_sha256")

    hard_invalid = proc.get("early_exit") is True
    qualified = all([
        readiness.get("workbench_window_logdir_and_renderer_log_and_state_db") is True,
        proc.get("early_exit") is False,
    ])
    validity = "INVALID" if hard_invalid else ("VALID" if qualified else "QUALIFIED")

# ---------- 3. OBSERVATION ----------
observed = "NOT_ASSESSED"
if not integrity_fails and validity != "INVALID" and m:
    bodies = raw_bodies
    evs = []
    parse_errors = 0
    for b in bodies:
        try:
            rec = json.loads(b)
        except (ValueError, UnicodeDecodeError):
            parse_errors += 1
            continue
        if isinstance(rec, dict) and rec.get("category") == "event":
            evs.append(rec)
    icheck("breadcrumb bodies parse as JSON records", parse_errors == 0,
           f"{parse_errors} unparseable")

    cl = m["synthetic_inputs"]["claude"]
    cx = m["synthetic_inputs"]["codex"]

    def utf16_len(s):
        # JavaScript String.length = UTF-16 code units.
        return len(s.encode("utf-16-le")) // 2

    if m.get("history_mode") == "canary":
        cl_ev = [e for e in evs if e.get("data", {}).get("sessionId") == cl["sessionId"]]
        cx_ev = [e for e in evs if e.get("data", {}).get("sessionId") == cx["session_id"]]

        ocheck("claude canary sessionId observed", len(cl_ev) >= 1)
        if cl_ev:
            d = cl_ev[0].get("data", {})
            ocheck("claude ts matches input ms exactly",
                   d.get("ts") == cl["timestamp_ms"],
                   f"{d.get('ts')} vs {cl['timestamp_ms']}")
            inp = os.path.join(ev, cl.get("packaged_file") or "inputs/claude-history.jsonl")
            if os.path.exists(inp):
                text = json.loads(open(inp).read())["display"]
                ocheck("claude n == UTF-16 code-unit length",
                       d.get("n") == utf16_len(text),
                       f"{d.get('n')} vs {utf16_len(text)}")
            else:
                ocheck("claude n check", False, "packaged input missing — no downgrade")

        ocheck("codex canary sessionId observed", len(cx_ev) >= 1)
        if cx_ev:
            d = cx_ev[0].get("data", {})
            # Event ts is milliseconds; input ts is SECONDS → compare to ms.
            expected_ms = cx["ts_seconds"] * 1000
            ocheck("codex ts == input seconds * 1000",
                   d.get("ts") == expected_ms,
                   f"{d.get('ts')} vs {expected_ms}")
            inp = os.path.join(ev, cx.get("packaged_file") or "inputs/codex-history.jsonl")
            if os.path.exists(inp):
                text = json.loads(open(inp).read())["text"]
                ocheck("codex n == UTF-16 code-unit length",
                       d.get("n") == utf16_len(text),
                       f"{d.get('n')} vs {utf16_len(text)}")
            else:
                ocheck("codex n check", False, "packaged input missing — no downgrade")

        # bookmarks: exact key + parsed value, never substring search
        bm = {}
        sp = os.path.join(ev, "state-vscdb-scoped.txt")
        if os.path.exists(sp):
            for line in open(sp):
                if "|" in line:
                    k, _, v = line.rstrip("\n").partition("|")
                    bm[k] = v
        ocheck("claude lastTimestamp bookmark exact",
               bm.get("externalCliAnalytics.lastTimestamp.claude") == str(cl["timestamp_ms"]),
               bm.get("externalCliAnalytics.lastTimestamp.claude", "absent"))
        ocheck("codex lastTimestamp bookmark exact",
               bm.get("externalCliAnalytics.lastTimestamp.codex") == str(cx["ts_seconds"] * 1000),
               bm.get("externalCliAnalytics.lastTimestamp.codex", "absent"))

        observed = "OBSERVED" if not obs_fails else "NOT_OBSERVED_WITHIN_WINDOW"
    else:
        ocheck("no ex_hs2 in none-history run",
               len([e for e in evs if str(e.get("message", "")).startswith("ex_hs")]) == 0)
        observed = "NOT_OBSERVED_WITHIN_WINDOW" if obs_fails == [] else "OBSERVED"

    # timing sanity (info-level, uses distinct phase epochs)
    if evs and m.get("phases", {}).get("launch_epoch_s") is not None:
        first = min(e.get("timestamp", 0) for e in evs)
        delta = first - m["phases"]["launch_epoch_s"]
        print(f"INFO first recorded event at +{delta:.3f}s after launch epoch")

# a mid-observation integrity failure (e.g. unparseable breadcrumb) must
# veto an OBSERVED verdict computed inside the same block.
if integrity_fails:
    observed = "NOT_ASSESSED"

print()
print(f"EVIDENCE_INTEGRITY = {'PASS' if not integrity_fails else 'FAIL ' + str(integrity_fails)}")
print(f"RUN_VALIDITY       = {validity}")
print(f"OBSERVATION        = {observed}")
sys.exit(0 if not integrity_fails and validity != "INVALID" else 1)
PYEOF
