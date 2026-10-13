#!/bin/bash
# test-runner-stub.sh — exercise run-experiment.sh against a benign stub
# target (never the real Cursor). Covers: delayed readiness, early exit,
# never-ready, cancellation, pin refusal, workbench-JS mismatch, and a
# full extract->verify pipeline pass on stub-produced evidence.
#
# Run: bash test-runner-stub.sh [scratch_dir]

set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SCRATCH="${1:-/tmp/rea-runner-stub}"
rm -rf "$SCRATCH"; mkdir -p "$SCRATCH"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "PASS $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL $1: $2"; }

# --- build a fake .app bundle ------------------------------------------
APP="$SCRATCH/StubApp"
BIN="$APP/Contents/MacOS/StubTarget"
WB="$APP/Contents/Resources/app/out/vs/workbench/workbench.desktop.main.js"
mkdir -p "$(dirname "$BIN")" "$(dirname "$WB")"
cat > "$BIN" <<'EOF'
#!/bin/bash
# Stub target: honors --stub-mode={delayed-ready,early-exit,never-ready,events}
UDD=""; MODE=normal
for a in "$@"; do
  case "$a" in
    --user-data-dir=*) UDD="${a#--user-data-dir=}" ;;
    --stub-mode=*)     MODE="${a#--stub-mode=}" ;;
  esac
done
[ "$MODE" = early-exit ] && exit 1
[ "$MODE" = delayed-ready ] && sleep 8
mkdir -p "$UDD/logs/2026T00/window1_wb1" "$UDD/User/globalStorage"
if [ "$MODE" != never-ready ]; then
  echo "renderer boot ok" > "$UDD/logs/2026T00/window1_wb1/renderer.log"
  /usr/bin/python3 -c 'import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); c.execute("CREATE TABLE ItemTable (key TEXT PRIMARY KEY, value TEXT)"); c.commit(); c.close()' "$UDD/User/globalStorage/state.vscdb"
fi
if [ "$MODE" = events ]; then
  /usr/bin/python3 - "$HOME" "$UDD" <<'PY'
import json, os, sqlite3, sys, time
home, udd = sys.argv[1], sys.argv[2]
cl = json.loads(open(os.path.join(home, ".claude/history.jsonl")).read().strip())
cx = json.loads(open(os.path.join(home, ".codex/history.jsonl")).read().strip())
def u16(s): return len(s.encode("utf-16-le")) // 2
evs = []
if cl.get("sessionId"):
    evs.append({"timestamp": time.time(), "category": "event",
                "message": "ex_hs2",
                "data": {"tool": "ac", "ts": cl["timestamp"],
                         "sessionId": cl["sessionId"], "n": u16(cl["display"])}})
if cx.get("session_id"):
    evs.append({"timestamp": time.time(), "category": "event",
                "message": "ex_hs2",
                "data": {"tool": "cx", "ts": cx["ts"] * 1000,
                         "sessionId": cx["session_id"], "n": u16(cx["text"])}})
with open(os.path.join(udd, "logs/2026T00/window1_wb1/cursor-sentry-events.log"), "w") as f:
    f.writelines(json.dumps(e) + "\n" for e in evs)
db = os.path.join(udd, "User/globalStorage/state.vscdb")
con = sqlite3.connect(db)
con.execute("CREATE TABLE IF NOT EXISTS ItemTable (key TEXT PRIMARY KEY, value TEXT)")
if cl.get("sessionId"):
    con.execute("INSERT INTO ItemTable VALUES (?,?)",
                ("externalCliAnalytics.lastTimestamp.claude", str(cl["timestamp"])))
if cx.get("session_id"):
    con.execute("INSERT INTO ItemTable VALUES (?,?)",
                ("externalCliAnalytics.lastTimestamp.codex", str(cx["ts"] * 1000)))
con.commit(); con.close()
PY
fi
sleep 600
EOF
chmod +x "$BIN"
echo "// stub workbench artifact" > "$WB"

BIN_SHA=$(shasum -a 256 "$BIN" | awk '{print $1}')
WB_SHA=$(shasum -a 256 "$WB" | awk '{print $1}')
RR="$SCRATCH/runs"
run_exp() {
  bash "$HERE/run-experiment.sh" --runs-root "$RR" \
    --cursor-app "$BIN" --expect-sha256 "$BIN_SHA" \
    --expect-workbench-sha256 "$WB_SHA" "$@"
}
latest_manifest() { ls -t "$RR"/stub-*/run-manifest.json 2>/dev/null | head -1; }

# --- T1: pin refusal — --cursor-app without --expect-sha256 -------------
bash "$HERE/run-experiment.sh" --runs-root "$RR" --cursor-app "$BIN" \
  --history canary --duration 5 >/dev/null 2>&1
[ $? -eq 2 ] && ok "T1-unpinned-custom-path-refused" || bad "T1" "expected exit 2"

# --- T2: workbench JS mismatch refused ---------------------------------
bash "$HERE/run-experiment.sh" --runs-root "$RR" \
  --cursor-app "$BIN" --expect-sha256 "$BIN_SHA" \
  --expect-workbench-sha256 "f00d" --history canary --duration 5 >/dev/null 2>&1
[ $? -eq 1 ] && ok "T2-workbench-mismatch-refused" || bad "T2" "expected exit 1"

# --- T3: delayed readiness — logs appear at +8s inside timeout ---------
run_exp --label stub --history none --duration 25 --ready-timeout 45 \
  --extra-arg --stub-mode=delayed-ready >/dev/null 2>&1
M=$(latest_manifest)
python3 - "$M" <<'PY' && ok "T3-delayed-ready-manifest" || bad "T3" "$(cat "$M" 2>/dev/null | head -3)"
import json, sys
m = json.load(open(sys.argv[1]))
assert m["readiness"]["workbench_window_logdir_and_renderer_log_and_state_db"] is True
assert m["process"]["early_exit"] is False
assert m["phases"]["ready_epoch_s"] and m["phases"]["observed_window_s"]
assert 0 < m["phases"]["observed_window_s"] < m["phases"]["requested_duration_s"]
PY

# --- T4: early exit → manifest exists, early_exit flagged --------------
run_exp --label stub --history none --duration 20 --ready-timeout 40 \
  --extra-arg --stub-mode=early-exit >/dev/null 2>&1
M=$(latest_manifest)
python3 - "$M" <<'PY' && ok "T4-early-exit-manifest" || bad "T4" "manifest missing/invalid"
import json, sys
m = json.load(open(sys.argv[1]))
assert m["process"]["early_exit"] is True
assert m["phases"]["launch_epoch_s"] is not None
PY

# --- T5: never ready → ready=false, manifest written -------------------
run_exp --label stub --history none --duration 15 --ready-timeout 8 \
  --extra-arg --stub-mode=never-ready >/dev/null 2>&1
M=$(latest_manifest)
python3 - "$M" <<'PY' && ok "T5-never-ready-manifest" || bad "T5" "manifest missing/invalid"
import json, sys
m = json.load(open(sys.argv[1]))
assert m["readiness"]["workbench_window_logdir_and_renderer_log_and_state_db"] is False
assert m["phases"]["observed_window_s"] is None
PY

# --- T6: cancellation — TERM during observation → manifest written ---
# (non-interactive bash ignores SIGINT for background jobs; SIGTERM
# exercises the same trap path)
bash "$HERE/run-experiment.sh" --runs-root "$RR" \
  --cursor-app "$BIN" --expect-sha256 "$BIN_SHA" \
  --expect-workbench-sha256 "$WB_SHA" \
  --label stub --history none --duration 120 --ready-timeout 45 \
  --extra-arg --stub-mode=delayed-ready >/dev/null 2>&1 &
RUNNER=$!
sleep 20
kill -TERM "$RUNNER" 2>/dev/null || true
wait "$RUNNER" 2>/dev/null
M=$(latest_manifest)
python3 - "$M" <<'PY' && ok "T6-cancelled-manifest" || bad "T6" "manifest missing/invalid"
import json, sys
m = json.load(open(sys.argv[1]))
assert m["process"]["cancelled"] is True
PY

# --- T7: full pipeline — stub writes canary events, extract + verify ---
run_exp --label stub --history canary --duration 25 --ready-timeout 45 \
  --extra-arg --stub-mode=events >/dev/null 2>&1
RD=$(ls -td "$RR"/stub-*/ | head -1)
bash "$HERE/extract-evidence.sh" --run "$RD" --out "$SCRATCH/pkg-t7" >/dev/null 2>&1
V=$(bash "$HERE/verify-evidence.sh" --evidence "$SCRATCH/pkg-t7" 2>&1)
echo "$V" | grep -q "OBSERVATION        = OBSERVED" && \
echo "$V" | grep -q "ELIGIBLE_FOR_COMPARISON = YES" \
  && ok "T7-stub-e2e-observed" || bad "T7" "$V"

echo; echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
