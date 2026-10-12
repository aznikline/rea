#!/bin/bash
# run-experiment.sh — create an isolated Cursor run with a unique run directory.
#
# Responsibilities: create run dir + fake HOME, write synthetic inputs,
# launch the target, record PID/timing, wait, terminate, freeze evidence.
# It does NOT extract or analyze evidence — that is extract-evidence.sh.
#
# Usage:
#   run-experiment.sh --history {none|canary} [--cursor-app PATH]
#                     [--duration SECS] [--runs-root DIR] [--label NAME]
#                     [--extra-arg ARG]...  (repeatable; recorded verbatim)
#
# Outputs $RUN_DIR/run-manifest.json with run id, args, intervention flags,
# PIDs, and timestamps. Evidence inputs are hashed into inputs-hashes.txt.

set -euo pipefail

HISTORY=canary
DURATION=120
RUNS_ROOT=/tmp/rea-cursor-runs
CURSOR_APP="/Users/wizout/op/targets/cursor/cursor-3.24.12/Cursor.app/Contents/MacOS/Cursor"
CURSOR_VERSION="3.24.12 (commit 37b865941ccb31e2fc90c685157534efca87f964; dmg sha256 c5ed7193bfb906e2aae3f3f281c62cb979efd1b662c73524a15f1c4448734f5f)"
LABEL=run
EXTRA_ARGS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --history) HISTORY=$2; shift 2 ;;
    --duration) DURATION=$2; shift 2 ;;
    --runs-root) RUNS_ROOT=$2; shift 2 ;;
    --cursor-app) CURSOR_APP=$2; shift 2 ;;
    --label) LABEL=$2; shift 2 ;;
    --extra-arg) EXTRA_ARGS+=("$2"); shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

case "$HISTORY" in none|canary) ;; *) echo "--history must be none|canary" >&2; exit 2 ;; esac

RUN_ID="${LABEL}-$(date +%s)-$$"
RUN_DIR="$RUNS_ROOT/$RUN_ID"
FH="$RUN_DIR/home"
mkdir -p "$FH/.claude" "$FH/.codex" "$FH/cursor-data"

START_EPOCH=$(python3 -c 'import time; print(f"{time.time():.3f}")')
CANARY_TS_CLAUDE=$(python3 -c 'import time; print(int((time.time()-10000)*1000))')
CANARY_TS_CODEX=$(python3 -c 'import time; print(int(time.time()-8000))')

if [ "$HISTORY" = canary ]; then
  CLAUDE_SID="${RUN_ID}-canary-claude"
  CODEX_SID="${RUN_ID}-canary-codex"
  printf '%s\n' "{\"display\":\"REA_R32_CANARY_CLAUDE synthetic entry ${RUN_ID}\",\"timestamp\":${CANARY_TS_CLAUDE},\"project\":\"/tmp/rea-r3\",\"sessionId\":\"${CLAUDE_SID}\"}" > "$FH/.claude/history.jsonl"
  printf '%s\n' "{\"session_id\":\"${CODEX_SID}\",\"ts\":${CANARY_TS_CODEX},\"text\":\"REA_R32_CANARY_CODEX synthetic entry ${RUN_ID}\"}" > "$FH/.codex/history.jsonl"
else
  CLAUDE_SID=""
  CODEX_SID=""
  : > "$FH/.claude/history.jsonl"
  : > "$FH/.codex/history.jsonl"
fi

(cd "$FH" && shasum -a 256 .claude/history.jsonl .codex/history.jsonl) > "$RUN_DIR/inputs-hashes.txt"

# Intervention params are explicit: --disable-crash-reporter is NOT a default
# launch and is recorded in the manifest as an intervention.
LAUNCH_ARGS=("--user-data-dir=$FH/cursor-data" "--disable-crash-reporter" "${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}")

env HOME="$FH" XDG_CONFIG_HOME="$FH/.config" \
  "$CURSOR_APP" "${LAUNCH_ARGS[@]}" > "$RUN_DIR/launch.log" 2>&1 &
LAUNCH_PID=$!

sleep "$DURATION"

END_EPOCH=$(python3 -c 'import time; print(f"{time.time():.3f}")')

# Terminate the recorded tree: children of the launch pid first, then the pid.
CHILDREN=$(pgrep -P "$LAUNCH_PID" 2>/dev/null || true)
for p in $CHILDREN; do
  for g in $(pgrep -P "$p" 2>/dev/null); do kill "$g" 2>/dev/null || true; done
  kill "$p" 2>/dev/null || true
done
kill "$LAUNCH_PID" 2>/dev/null || true
sleep 2
for p in $LAUNCH_PID $CHILDREN; do kill -9 "$p" 2>/dev/null || true; done
wait "$LAUNCH_PID" 2>/dev/null || true

EXTRA_JSON=$(printf '%s\n' "${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}" | python3 -c 'import json,sys; print(json.dumps([l.rstrip("\n") for l in sys.stdin if l.strip()]))')
ARGS_JSON=$(printf '%s\n' "${LAUNCH_ARGS[@]}" | python3 -c 'import json,sys; print(json.dumps([l.rstrip("\n") for l in sys.stdin]))')

RUN_ID="$RUN_ID" HISTORY="$HISTORY" CURSOR_VERSION="$CURSOR_VERSION" \
CURSOR_APP="$CURSOR_APP" FH="$FH" START_EPOCH="$START_EPOCH" \
END_EPOCH="$END_EPOCH" DURATION="$DURATION" LAUNCH_PID="$LAUNCH_PID" \
CHILDREN="$CHILDREN" CLAUDE_SID="$CLAUDE_SID" CODEX_SID="$CODEX_SID" \
CANARY_TS_CLAUDE="$CANARY_TS_CLAUDE" CANARY_TS_CODEX="$CANARY_TS_CODEX" \
EXTRA_JSON="$EXTRA_JSON" ARGS_JSON="$ARGS_JSON" \
python3 - "$RUN_DIR/run-manifest.json" <<'PYEOF'
import json, os, sys, time, datetime
m = {
  "run_id": os.environ["RUN_ID"],
  "history_mode": os.environ["HISTORY"],
  "cursor_version_identity": os.environ["CURSOR_VERSION"],
  "cursor_app": os.environ["CURSOR_APP"],
  "fake_home": os.environ["FH"],
  "launch_args": json.loads(os.environ["ARGS_JSON"]),
  "interventions": {
    "disable_crash_reporter": True,
    "isolated_home": True,
    "isolated_user_data_dir": True,
    "login": "none",
    "extra_args": json.loads(os.environ["EXTRA_JSON"])
  },
  "synthetic_inputs": {
    "claude": {"file": f'{os.environ["FH"]}/.claude/history.jsonl',
               "sessionId": os.environ["CLAUDE_SID"],
               "timestamp_ms": int(os.environ["CANARY_TS_CLAUDE"])},
    "codex":  {"file": f'{os.environ["FH"]}/.codex/history.jsonl',
               "session_id": os.environ["CODEX_SID"],
               "ts_seconds": int(os.environ["CANARY_TS_CODEX"])}
  },
  "timing": {"start_epoch_s": float(os.environ["START_EPOCH"]),
             "start_utc": datetime.datetime.fromtimestamp(float(os.environ["START_EPOCH"]), datetime.timezone.utc).isoformat(),
             "end_epoch_s": float(os.environ["END_EPOCH"]),
             "duration_s": int(os.environ["DURATION"])},
  "launch_pid": int(os.environ["LAUNCH_PID"]),
  "child_pids": os.environ["CHILDREN"].split(),
  "written_at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat()
}
with open(sys.argv[1], "w") as f:
    json.dump(m, f, indent=2)
PYEOF

echo "run frozen: $RUN_DIR"
