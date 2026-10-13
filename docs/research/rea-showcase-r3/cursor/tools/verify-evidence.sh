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
# not a skip. Coverage is checked BOTH directions: every required file
# must be listed, and every listed path must stay inside the package.
covered = set()
hpath = os.path.join(ev, "hashes.txt")
if os.path.exists(hpath):
    n_entries = 0
    for line in open(hpath):
        parts = line.rsplit(None, 1)
        if len(parts) != 2:
            icheck("hashes.txt line parses", False, line.strip()[:60]); continue
        want, p = parts[0], parts[1].strip()
        n_entries += 1
        # path must be package-relative and non-escaping
        esc = os.path.isabs(p) or ".." in p.split("/")
        if esc:
            icheck(f"hash path in-package {p}", False, "absolute or escaping path")
            continue
        covered.add(p)
        path = os.path.join(ev, p)
        if os.path.exists(path):
            got = hashlib.sha256(open(path, "rb").read()).hexdigest()
            icheck(f"hash {p}", got == want, got[:12])
        else:
            icheck(f"hash {p}", False, "referenced file missing")
    icheck("hashes.txt non-empty", n_entries > 0, f"{n_entries} entries")
else:
    covered = set()

# packaged inputs must exist inside the package — resolved via manifest
# `packaged_file`, with the extractor's conventional path as fallback
# for manifests written before the field existed.
if m:
    canon = m.get("synthetic_inputs", {})
    for side in ("claude", "codex"):
        rel = canon.get(side, {}).get("packaged_file") or f"inputs/{side}-history.jsonl"
        icheck(f"{side} packaged input exists",
               os.path.exists(os.path.join(ev, rel)), rel)
        # existence is NOT hash coverage — do not add to `covered`

# complete package: EVERY file on disk (except hashes.txt itself) must be
# listed in hashes.txt — a manifest that only covers some files does not
# certify the package.
if os.path.exists(hpath):
    on_disk = set()
    for dp, _, fns in os.walk(ev):
        for fn in fns:
            if fn != "hashes.txt":
                on_disk.add(os.path.relpath(os.path.join(dp, fn), ev))
    uncovered = sorted(on_disk - covered)
    icheck("all package files are hash-covered", not uncovered, str(uncovered))

# manifest must agree with the ACTUAL packaged inputs (not just its claims)
if m:
    canon = m.get("synthetic_inputs", {})
    for side, key, tskey in (("claude", "sessionId", "timestamp"),
                             ("codex", "session_id", "ts")):
        rel = canon.get(side, {}).get("packaged_file") or f"inputs/{side}-history.jsonl"
        p = os.path.join(ev, rel)
        if os.path.exists(p):
            raw = open(p).read().strip()
            if not raw:
                # "no records" is a real input state (history_mode=none
                # writes zero-byte history files). It is legitimate for
                # none mode, corrupt for canary mode.
                icheck(f"{side} packaged input parses",
                       m.get("history_mode") == "none",
                       "empty input file" + ("" if m.get("history_mode") == "none"
                                             else " in canary mode"))
                continue
            try:
                inp = json.loads(raw)
                if side == "claude":
                    icheck("claude input sessionId matches manifest",
                           inp.get(key) == canon[side].get("sessionId"),
                           f"{inp.get(key)} vs {canon[side].get('sessionId')}")
                    icheck("claude input timestamp matches manifest",
                           inp.get(tskey) == canon[side].get("timestamp_ms"),
                           f"{inp.get(tskey)} vs {canon[side].get('timestamp_ms')}")
                else:
                    icheck("codex input session_id matches manifest",
                           inp.get(key) == canon[side].get("session_id"),
                           f"{inp.get(key)} vs {canon[side].get('session_id')}")
                    icheck("codex input ts matches manifest",
                           inp.get(tskey) == canon[side].get("ts_seconds"),
                           f"{inp.get(tskey)} vs {canon[side].get('ts_seconds')}")
            except (ValueError, KeyError) as e:
                icheck(f"{side} packaged input parses", False, str(e)[:60])

# extract-report parse health
report = {}
rpath = os.path.join(ev, "extract-report.json")
if os.path.exists(rpath):
    try:
        report = json.load(open(rpath))
        icheck("no extractor file errors", not report.get("files_with_errors"),
               str(report.get("files_with_errors"))[:80])
        # records carrying event markers that failed to parse must fail
        # integrity — they cannot be silently counted as zero events.
        icheck("no unparsed event-marker candidates",
               not report.get("unparsed_candidates"),
               str(report.get("unparsed_candidates"))[:120])
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
    req_phases = ["probe_epoch_s", "launch_epoch_s", "obs_end_epoch_s"]
    if readiness.get("workbench_window_logdir_and_renderer_log_and_state_db") is True:
        req_phases.append("ready_epoch_s")
    vcheck("phase epochs recorded",
           all(phases.get(k) is not None for k in req_phases))
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

# eligibility for formal matrix comparison — warnings DO gate eligibility
ineligible = []
if m:
    if proc.get("early_exit") is True:
        ineligible.append("early_exit")
    if proc.get("cancelled") is True:
        ineligible.append("cancelled")
    if readiness.get("workbench_window_logdir_and_renderer_log_and_state_db") is not True:
        ineligible.append("workbench_readiness_not_reached")
    elif phases.get("ready_epoch_s") is None:
        ineligible.append("ready_epoch_missing")
    if proc.get("post_termination_remaining_processes") not in (0, "0"):
        ineligible.append("cleanup_incomplete")
    if tgt.get("identity") not in ("match",):
        ineligible.append(f"target_identity_{tgt.get('identity', 'unknown')}")
    wb = tgt.get("workbench_js") or {}
    if wb.get("identity") not in ("match",):
        ineligible.append(f"workbench_js_identity_{wb.get('identity', 'unknown')}")
    if not all(phases.get(k) is not None for k in
               ("probe_epoch_s", "launch_epoch_s", "obs_end_epoch_s")):
        ineligible.append("phase_epochs_missing")

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
        # Observation binds: event name == "ex_hs2" AND the expected `tool`
        # AND the planted sessionId AND fields matching the packaged input
        # AND the record lands inside this run's time window.
        # An event with our sessionId but wrong name/tool/fields is NOT
        # "not observed" — it is FIELD_MISMATCH.
        phases = m.get("phases", {})
        launch = phases.get("launch_epoch_s")
        obs_end = phases.get("obs_end_epoch_s")
        def in_window(e):
            # missing window endpoints: unverifiable, not a pass and not
            # a crash — a soft mismatch keeping the run out of OBSERVED.
            if launch is None or obs_end is None:
                return None
            return launch - 5 <= e.get("timestamp", 0) <= obs_end + 5
        mismatched = []      # hard: fields or window bound and wrong
        soft_mismatch = []   # window unverifiable — cannot attribute to run

        def match_side(sid, tool, ts_ok, text, inp_rel):
            cands = [e for e in evs if e.get("data", {}).get("sessionId") == sid]
            good = []
            for e in cands:
                reasons = []
                if e.get("message") != "ex_hs2":
                    reasons.append(f"message={e.get('message')!r}")
                if e.get("data", {}).get("tool") != tool:
                    reasons.append(f"tool={e.get('data', {}).get('tool')!r}")
                if not ts_ok(e.get("data", {}).get("ts")):
                    reasons.append(f"ts={e.get('data', {}).get('ts')!r}")
                inp = os.path.join(ev, inp_rel)
                if os.path.exists(inp):
                    want_n = utf16_len(text)
                    if e.get("data", {}).get("n") != want_n:
                        reasons.append(f"n={e.get('data', {}).get('n')!r} want {want_n}")
                else:
                    reasons.append("packaged input missing — n unverifiable")
                w = in_window(e)
                if w is None:
                    soft_mismatch.append({"sessionId": sid,
                                          "reasons": ["run window unverifiable"]})
                    continue
                if not w:
                    reasons.append("record timestamp outside run window")
                if reasons:
                    mismatched.append({"sessionId": sid, "reasons": reasons})
                else:
                    good.append(e)
            return cands, good

        cl_text = cx_text = None
        cl_inp_rel = cl.get("packaged_file") or "inputs/claude-history.jsonl"
        cx_inp_rel = cx.get("packaged_file") or "inputs/codex-history.jsonl"
        if os.path.exists(os.path.join(ev, cl_inp_rel)):
            cl_text = json.loads(open(os.path.join(ev, cl_inp_rel)).read())["display"]
        if os.path.exists(os.path.join(ev, cx_inp_rel)):
            cx_text = json.loads(open(os.path.join(ev, cx_inp_rel)).read())["text"]

        cl_c, cl_ev = match_side(cl["sessionId"], "ac",
            lambda ts: ts == cl["timestamp_ms"], cl_text or "", cl_inp_rel)
        cx_c, cx_ev = match_side(cx["session_id"], "cx",
            lambda ts: ts == cx["ts_seconds"] * 1000, cx_text or "", cx_inp_rel)

        ocheck("claude canary event observed (ex_hs2/ac/fields bound)", len(cl_ev) >= 1,
               f"{len(cl_c)} sessionId candidates, {len(cl_ev)} fully bound")
        ocheck("codex canary event observed (ex_hs2/cx/fields bound)", len(cx_ev) >= 1,
               f"{len(cx_c)} sessionId candidates, {len(cx_ev)} fully bound")
        ocheck("no field-mismatched candidates", not mismatched, str(mismatched))
        if soft_mismatch:
            print(f"INFO window-unverifiable candidates: {soft_mismatch}")

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

        if mismatched:
            observed = "FIELD_MISMATCH"
        elif cl_ev or cx_ev:
            # at least one side fully bound; leftover failures mean partial
            observed = "OBSERVED" if not obs_fails else "OBSERVED_PARTIAL"
        elif cl_c or cx_c:
            # candidates exist but none could be fully bound to this run
            # (e.g. window endpoints missing) — partial observation, never
            # folded into "not observed".
            observed = "OBSERVED_PARTIAL"
        else:
            observed = "NOT_OBSERVED_WITHIN_WINDOW"
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
print(f"ELIGIBLE_FOR_COMPARISON = {'YES' if not integrity_fails and validity == 'VALID' and not ineligible else 'NO'}")
if ineligible:
    print(f"INELIGIBILITY_REASONS = {ineligible}")
sys.exit(0 if not integrity_fails and validity != "INVALID" else 1)
PYEOF
