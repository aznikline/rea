#!/bin/bash
# verify-evidence.sh — verify an extracted evidence directory.
#
# Does NOT launch the target. Checks: evidence file hashes, synthetic-input
# hashes, canary field correspondence (sessionId/timestamp/n=char length),
# event-vs-launch timing, and reports raw vs deduplicated record counts.
#
# Usage: verify-evidence.sh --evidence OUT_DIR
# Exit: 0 = all checks passed; 1 = at least one check failed.

set -euo pipefail

EV=""
while [ $# -gt 0 ]; do
  case "$1" in --evidence) EV=$2; shift 2 ;; *) echo "unknown arg: $1" >&2; exit 2 ;; esac
done
[ -n "$EV" ] || { echo "usage: verify-evidence.sh --evidence OUT_DIR" >&2; exit 2; }
[ -f "$EV/run-manifest.json" ] || { echo "no run-manifest.json" >&2; exit 1; }

EV="$EV" python3 <<'PYEOF'
import hashlib, json, os, re, sys

ev = os.environ["EV"]
m = json.load(open(os.path.join(ev, "run-manifest.json")))
fails = []
def check(name, ok, detail=""):
    print(f"{'PASS' if ok else 'FAIL'} {name} {detail}")
    if not ok: fails.append(name)

# 1. evidence hashes
recorded = {}
hpath = os.path.join(ev, "hashes.txt")
if os.path.exists(hpath):
    for line in open(hpath):
        parts = line.split()
        if len(parts) == 2: recorded[os.path.basename(parts[1])] = parts[0]
for fn, want in recorded.items():
    p = os.path.join(ev, fn)
    if not os.path.exists(p):
        p = os.path.join(os.path.dirname(ev), fn)  # inputs live outside
    if os.path.exists(p):
        got = hashlib.sha256(open(p, "rb").read()).hexdigest()
        check(f"hash {fn}", got == want, got[:12])
    else:
        check(f"hash {fn}", False, "file not found (may be input outside evidence dir)")

# 2. raw vs deduped breadcrumb counts
raw = open(os.path.join(ev, "breadcrumbs-raw.txt")).read().splitlines()
ded = open(os.path.join(ev, "breadcrumbs-deduped.txt")).read().splitlines()
check("dedup is a subset of raw", len(ded) <= len(raw), f"raw={len(raw)} dedup={len(ded)}")
dupes = len(raw) - len(ded)
print(f"INFO duplicate raw records: {dupes} (raw counts are NOT distinct events)")

# 3. canary field correspondence
canon = m["synthetic_inputs"]
bodies = [l.split(": ", 1)[-1] for l in raw]
evs = []
for b in bodies:
    mm = re.search(r'\{"timestamp":([0-9.]+),"category":"event","message":"(ex_hs[0-9]*)","data":(\{.*\})\}', b)
    if mm: evs.append({"ts": float(mm.group(1)), "msg": mm.group(2), "data": json.loads(mm.group(3))})

cl = canon["claude"]; cx = canon["codex"]
cl_ev = [e for e in evs if e["data"].get("sessionId") == cl["sessionId"]]
cx_ev = [e for e in evs if e["data"].get("sessionId") == cx["session_id"]]

if m["history_mode"] == "canary":
    check("claude canary sessionId observed", len(cl_ev) >= 1)
    if cl_ev:
        check("claude ts matches input ms", cl_ev[0]["data"].get("ts") == cl["timestamp_ms"], f"{cl_ev[0]['data'].get('ts')} vs {cl['timestamp_ms']}")
        # n = character length of the synthesized display text; the input file
        # records the exact bytes that were written.
        input_file = cl["file"]
        if os.path.exists(input_file):
            n_expected = len(json.loads(open(input_file).read())["display"])
            check("claude n == display char length", cl_ev[0]["data"].get("n") == n_expected,
                  f"{cl_ev[0]['data'].get('n')} vs {n_expected}")
        else:
            check("claude n is int", isinstance(cl_ev[0]["data"].get("n"), int))
    check("codex canary sessionId observed", len(cx_ev) >= 1)
    if cx_ev:
        check("codex ts matches input s", cx_ev[0]["data"].get("ts") == cx["ts_seconds"], f"{cx_ev[0]['data'].get('ts')} vs {cx['ts_seconds']}")
        input_file = cx["file"]
        if os.path.exists(input_file):
            n_expected = len(json.loads(open(input_file).read())["text"])
            check("codex n == text char length", cx_ev[0]["data"].get("n") == n_expected,
                  f"{cx_ev[0]['data'].get('n')} vs {n_expected}")
else:
    check("no canary ex_hs2 in none-history run", len([e for e in evs if e["msg"] == "ex_hs2"]) == 0)

# 4. timing: first event after launch
if evs:
    first = min(e["ts"] for e in evs)
    delta = first - m["timing"]["start_epoch_s"]
    print(f"INFO first recorded event at +{delta:.3f}s after launch epoch")
    check("event timestamp after launch", delta > 0)

# 5. bookmark correspondence in scoped sqlite
sq = open(os.path.join(ev, "state-vscdb-scoped.txt")).read()
if m["history_mode"] == "canary":
    check("claude lastTimestamp bookmark", str(cl["timestamp_ms"]) in sq)
    check("codex lastTimestamp bookmark", str(cx["ts_seconds"]) in sq)

print(f"\n{'VERDICT: PASS' if not fails else 'VERDICT: FAIL ' + str(fails)}")
sys.exit(1 if fails else 0)
PYEOF
