#!/bin/bash
# run-experiment.sh — create an isolated Cursor run with a unique run directory.
#
# Responsibilities: create run dir + fake HOME, write synthetic inputs,
# launch the target, watch readiness, observe, terminate, freeze evidence.
# It does NOT extract or analyze — that is extract-evidence.sh.
# It does NOT judge results — that is verify-evidence.sh.
#
# Usage:
#   run-experiment.sh --history {none|canary} [--cursor-app PATH]
#                     [--expect-sha256 HEX] [--expect-workbench-sha256 HEX]
#                     [--duration SECS] [--ready-timeout SECS]
#                     [--runs-root DIR] [--label NAME]
#                     [--extra-arg ARG]...  (repeatable; recorded verbatim)
#
# Identity contract:
#   * The default target is pinned to the 3.24.12 Mach-O AND to the
#     workbench.desktop.main.js artifact actually containing the code
#     under study.
#   * --cursor-app alone is REFUSED: a different path does not silently
#     drop the pin. A non-default path requires --expect-sha256 (and
#     --expect-workbench-sha256 if the bundle layout still applies).
#
# Phase model recorded in run-manifest.json:
#   probe -> launch -> readiness-wait -> observation-window -> terminate
# Readiness is measured independently of ex_hs2 events. A run whose target
# exits early is INVALID, not a negative result. The manifest is written
# by the EXIT trap so every terminal path produces a terminal record.

set -euo pipefail

HISTORY=canary
DURATION=240
READY_TIMEOUT=90
RUNS_ROOT=/tmp/rea-cursor-runs
DEFAULT_APP="/Users/wizout/op/targets/cursor/cursor-3.24.12/Cursor.app/Contents/MacOS/Cursor"
CURSOR_APP="$DEFAULT_APP"
# Expected identity for the pinned 3.24.12 artifact — sha256 of the
# Contents/MacOS/Cursor Mach-O binary itself (NOT the dmg/zip container
# hash c5ed7193…, which covers a different byte stream), and of the
# workbench JS artifact that holds the code under study.
EXPECTED_SHA256="71e8dfc19ff2216a277315972dcca0ea83773e8ec214f3cf352ee9591ce38037"
EXPECTED_WB_SHA256="044ce0931100af5fe95403e9a692b02932bc3e13a6763f576b851f503fefa518"
EXPLICIT_PIN=0
LABEL=run
EXTRA_ARGS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --history) HISTORY=$2; shift 2 ;;
    --duration) DURATION=$2; shift 2 ;;
    --ready-timeout) READY_TIMEOUT=$2; shift 2 ;;
    --runs-root) RUNS_ROOT=$2; shift 2 ;;
    --cursor-app) CURSOR_APP=$2; shift 2 ;;
    --expect-sha256) EXPECTED_SHA256=$2; EXPLICIT_PIN=1; shift 2 ;;
    --expect-workbench-sha256) EXPECTED_WB_SHA256=$2; shift 2 ;;
    --label) LABEL=$2; shift 2 ;;
    --extra-arg) EXTRA_ARGS+=("$2"); shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

case "$HISTORY" in none|canary) ;; *) echo "--history must be none|canary" >&2; exit 2 ;; esac
[ -x "$CURSOR_APP" ] || { echo "target not executable: $CURSOR_APP" >&2; exit 1; }

# A non-default target path REQUIRES an explicit pin — never unpinned.
if [ "$CURSOR_APP" != "$DEFAULT_APP" ] && [ "$EXPLICIT_PIN" = 0 ]; then
  echo "refusing: --cursor-app requires --expect-sha256 (path may change, identity may not silently unpinned)" >&2
  exit 2
fi

SCRIPT_SELF_SHA=$(shasum -a 256 "$0" | awk '{print $1}')
COMPUTED_SHA=$(shasum -a 256 "$CURSOR_APP" | awk '{print $1}')
IDENTITY_MATCH="unknown"
[ -n "$EXPECTED_SHA256" ] && [ "$COMPUTED_SHA" = "$EXPECTED_SHA256" ] && IDENTITY_MATCH="match"
[ -n "$EXPECTED_SHA256" ] && [ "$COMPUTED_SHA" != "$EXPECTED_SHA256" ] && { echo "target sha256 mismatch: computed $COMPUTED_SHA expected $EXPECTED_SHA256" >&2; exit 1; }
[ -z "$EXPECTED_SHA256" ] && IDENTITY_MATCH="unpinned"

# workbench JS artifact identity — the code under study lives here, so
# pinning only the launch binary would not bind the analyzed bytes.
WB_JS="$(dirname "$CURSOR_APP")/../Resources/app/out/vs/workbench/workbench.desktop.main.js"
WB_JS_SHA=""
WB_IDENTITY="absent"
if [ -f "$WB_JS" ]; then
  WB_JS_SHA=$(shasum -a 256 "$WB_JS" | awk '{print $1}')
  if [ -n "$EXPECTED_WB_SHA256" ]; then
    [ "$WB_JS_SHA" = "$EXPECTED_WB_SHA256" ] && WB_IDENTITY="match" || {
      echo "workbench JS sha256 mismatch: computed $WB_JS_SHA expected $EXPECTED_WB_SHA256" >&2; exit 1; }
  else
    WB_IDENTITY="unpinned"
  fi
fi

RUN_ID="${LABEL}-$(date +%s)-$$"
RUN_DIR="$RUNS_ROOT/$RUN_ID"
FH="$RUN_DIR/home"
mkdir -p "$FH/.claude" "$FH/.codex" "$FH/cursor-data" "$FH/tmp"

CANARY_TS_CLAUDE=$(python3 -c 'import time; print(int((time.time()-10000)*1000))')
CANARY_TS_CODEX=$(python3 -c 'import time; print(int(time.time()-8000))')

if [ "$HISTORY" = canary ]; then
  CLAUDE_SID="${RUN_ID}-canary-claude"
  CODEX_SID="${RUN_ID}-canary-codex"
  printf '%s\n' "{\"display\":\"REA_R33_CANARY_CLAUDE synthetic entry ${RUN_ID}\",\"timestamp\":${CANARY_TS_CLAUDE},\"project\":\"/tmp/rea-r3\",\"sessionId\":\"${CLAUDE_SID}\"}" > "$FH/.claude/history.jsonl"
  printf '%s\n' "{\"session_id\":\"${CODEX_SID}\",\"ts\":${CANARY_TS_CODEX},\"text\":\"REA_R33_CANARY_CODEX synthetic entry ${RUN_ID}\"}" > "$FH/.codex/history.jsonl"
else
  CLAUDE_SID=""
  CODEX_SID=""
  : > "$FH/.claude/history.jsonl"
  : > "$FH/.codex/history.jsonl"
fi
(cd "$FH" && shasum -a 256 .claude/history.jsonl .codex/history.jsonl) > "$RUN_DIR/inputs-hashes.txt"

# --- phase: probe (network reachability BEFORE launch) ---
PROBE_EPOCH=$(python3 -c 'import time; print(f"{time.time():.3f}")')
NET_PROBE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 https://api2.cursor.sh/ 2>/dev/null || echo "unreachable")

# --- phase: launch ---
LAUNCH_ARGS=("--user-data-dir=$FH/cursor-data" "--disable-crash-reporter")
if [ ${#EXTRA_ARGS[@]} -gt 0 ]; then LAUNCH_ARGS+=("${EXTRA_ARGS[@]}"); fi

# env -i: minimal environ only. NOT an OS user/permission/filesystem
# boundary — the process still runs as the invoking user.
env -i HOME="$FH" XDG_CONFIG_HOME="$FH/.config" PATH=/usr/bin:/bin:/usr/sbin:/sbin \
  LANG=en_US.UTF-8 USER=rea-exp LOGNAME=rea-exp TMPDIR="$FH/tmp" \
  "$CURSOR_APP" "${LAUNCH_ARGS[@]}" > "$RUN_DIR/launch.log" 2>&1 &
LAUNCH_PID=$!
LAUNCH_EPOCH=$(python3 -c 'import time; print(f"{time.time():.3f}")')

TERMINATED=0
EARLY_EXIT=0
CANCELLED=0
READY=0
READY_EPOCH=""
OBS_END_EPOCH=""
REMAIN="unmeasured"
CHILDREN=""

write_manifest() {
  # Terminal manifest on EVERY exit path — success, failure, timeout,
  # cancellation. Called from the EXIT trap after cleanup.
  mkdir -p "$RUN_DIR"
  [ -z "$OBS_END_EPOCH" ] && OBS_END_EPOCH=$(python3 -c 'import time; print(f"{time.time():.3f}")')
  EXTRA_JSON=$(printf '%s\n' "${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}" | python3 -c 'import json,sys; print(json.dumps([l.rstrip("\n") for l in sys.stdin if l.strip()]))')
  ARGS_JSON=$(printf '%s\n' "${LAUNCH_ARGS[@]+"${LAUNCH_ARGS[@]}"}" | python3 -c 'import json,sys; print(json.dumps([l.rstrip("\n") for l in sys.stdin if l.strip()]))')

  RUN_ID="$RUN_ID" HISTORY="$HISTORY" CURSOR_APP="$CURSOR_APP" FH="$FH" \
  NET_PROBE="$NET_PROBE" PROBE_EPOCH="$PROBE_EPOCH" \
  LAUNCH_EPOCH="$LAUNCH_EPOCH" READY_EPOCH="$READY_EPOCH" READY="$READY" \
  OBS_END_EPOCH="$OBS_END_EPOCH" DURATION="$DURATION" READY_TIMEOUT="$READY_TIMEOUT" \
  LAUNCH_PID="$LAUNCH_PID" EARLY_EXIT="$EARLY_EXIT" CANCELLED="$CANCELLED" \
  REMAIN="$REMAIN" CHILDREN="${CHILDREN:-}" \
  CLAUDE_SID="$CLAUDE_SID" CODEX_SID="$CODEX_SID" \
  CANARY_TS_CLAUDE="$CANARY_TS_CLAUDE" CANARY_TS_CODEX="$CANARY_TS_CODEX" \
  EXTRA_JSON="$EXTRA_JSON" ARGS_JSON="$ARGS_JSON" \
  SCRIPT_SELF_SHA="$SCRIPT_SELF_SHA" COMPUTED_SHA="$COMPUTED_SHA" \
  EXPECTED_SHA256="$EXPECTED_SHA256" IDENTITY_MATCH="$IDENTITY_MATCH" \
  WB_JS="$WB_JS" WB_JS_SHA="$WB_JS_SHA" \
  EXPECTED_WB_SHA256="$EXPECTED_WB_SHA256" WB_IDENTITY="$WB_IDENTITY" \
  python3 - "$RUN_DIR/run-manifest.json" <<'PYEOF'
import json, os, sys, datetime
def f(v): return None if v in ("", "unmeasured") else float(v)
launch = f(os.environ["LAUNCH_EPOCH"])
ready  = f(os.environ["READY_EPOCH"])
obs    = f(os.environ["OBS_END_EPOCH"])
m = {
  "run_id": os.environ["RUN_ID"],
  "history_mode": os.environ["HISTORY"],
  "target": {
    "path": os.environ["CURSOR_APP"],
    "computed_sha256": os.environ["COMPUTED_SHA"],
    "expected_sha256": os.environ["EXPECTED_SHA256"] or None,
    "identity": os.environ["IDENTITY_MATCH"],
    "workbench_js": {
      "path": os.environ["WB_JS"],
      "computed_sha256": os.environ["WB_JS_SHA"] or None,
      "expected_sha256": os.environ["EXPECTED_WB_SHA256"] or None,
      "identity": os.environ["WB_IDENTITY"],
    },
  },
  "fake_home": os.environ["FH"],
  "launch_args": json.loads(os.environ["ARGS_JSON"]),
  "interventions": {
    "disable_crash_reporter": True,
    "isolated_home": "path redirect only — NOT filesystem/permission isolation",
    "isolated_user_data_dir": True,
    "login": "none",
    "extra_args": json.loads(os.environ["EXTRA_JSON"]),
    "environment": "env -i minimal environ (env-var scope only; NOT an OS user boundary)",
  },
  "synthetic_inputs": {
    "claude": {"packaged_file": "inputs/claude-history.jsonl",
               "source_file": f'{os.environ["FH"]}/.claude/history.jsonl',
               "sessionId": os.environ["CLAUDE_SID"],
               "timestamp_ms": int(os.environ["CANARY_TS_CLAUDE"])},
    "codex":  {"packaged_file": "inputs/codex-history.jsonl",
               "source_file": f'{os.environ["FH"]}/.codex/history.jsonl',
               "session_id": os.environ["CODEX_SID"],
               "ts_seconds": int(os.environ["CANARY_TS_CODEX"])},
  },
  "phases": {
    "probe_epoch_s": f(os.environ["PROBE_EPOCH"]),
    "probe_result": os.environ["NET_PROBE"],
    "launch_epoch_s": launch,
    "ready_epoch_s": ready,
    "obs_end_epoch_s": obs,
    "requested_duration_s": int(os.environ["DURATION"]),
    "ready_timeout_s": int(os.environ["READY_TIMEOUT"]),
    "total_runtime_s": (obs - launch) if (launch and obs) else None,
    "observed_window_s": (obs - ready) if (ready and obs) else None,
  },
  "readiness": {
    "workbench_window_logdir_and_renderer_log_and_state_db": bool(int(os.environ["READY"])),
    "basis": "window*_wb*/renderer.log non-empty AND state.vscdb exists — independent of ex_hs2",
  },
  "process": {
    "launch_pid": int(os.environ["LAUNCH_PID"]),
    "early_exit": bool(int(os.environ["EARLY_EXIT"])),
    "cancelled": bool(int(os.environ["CANCELLED"])),
    "child_pids": os.environ["CHILDREN"].split(),
    "post_termination_remaining_processes": os.environ["REMAIN"],
    "cleanup_incomplete": os.environ["REMAIN"] not in ("0", "unmeasured"),
  },
  "runner": {"script_sha256": os.environ["SCRIPT_SELF_SHA"]},
  "written_at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
}
with open(sys.argv[1], "w") as f_:
    json.dump(m, f_, indent=2)
PYEOF
}

cleanup_run() {
  [ "$TERMINATED" = 1 ] && return
  TERMINATED=1
  CHILDREN=$(pgrep -f "user-data-dir=$FH/cursor-data" 2>/dev/null | grep -v "^${LAUNCH_PID:-0}$" || true)
  for p in $CHILDREN ${LAUNCH_PID:-}; do kill "$p" 2>/dev/null || true; done
  sleep 3
  for p in $CHILDREN ${LAUNCH_PID:-}; do kill -9 "$p" 2>/dev/null || true; done
  REMAIN=$(pgrep -f "user-data-dir=$FH/cursor-data" 2>/dev/null | wc -l | tr -d ' ' || true)
}

on_exit() {
  cleanup_run
  write_manifest
  echo "run frozen: $RUN_DIR (ready=$READY early_exit=$EARLY_EXIT cancelled=$CANCELLED remaining=$REMAIN identity=$IDENTITY_MATCH wb=$WB_IDENTITY)"
}
trap on_exit EXIT
trap 'CANCELLED=1; exit 130' INT
trap 'CANCELLED=1; exit 143' TERM

# --- phase: readiness wait (independent of ex_hs2) ---
# "logs dir not yet created" is PENDING, not an error — guard the find so
# set -e/pipefail cannot abort the wait loop.
DEADLINE=$(( $(date +%s) + READY_TIMEOUT ))
while [ "$(date +%s)" -lt "$DEADLINE" ]; do
  if ! kill -0 "$LAUNCH_PID" 2>/dev/null; then EARLY_EXIT=1; break; fi
  WIN=""
  if [ -d "$FH/cursor-data/logs" ]; then
    WIN=$(find "$FH/cursor-data/logs" -maxdepth 2 -type d -name 'window*_wb*' 2>/dev/null | head -1 || true)
  fi
  DB="$FH/cursor-data/User/globalStorage/state.vscdb"
  if [ -n "$WIN" ] && [ -f "$DB" ] && \
     [ -n "$(find "$WIN" -name 'renderer.log' -size +0c 2>/dev/null | head -1 || true)" ]; then
    READY=1; READY_EPOCH=$(python3 -c 'import time; print(f"{time.time():.3f}")'); break
  fi
  sleep 5
done

# --- phase: observation window (only while the target lives) ---
# Total duration budget is counted from launch; the manifest records
# observed_window_s = obs_end - ready so matrix comparison uses the
# ACTUAL post-readiness observation length.
if [ "$EARLY_EXIT" = 0 ]; then
  ELAPSED=$(( $(date +%s) - ${LAUNCH_EPOCH%.*} ))
  SLEEP_LEFT=$(( DURATION - ELAPSED ))
  [ "$SLEEP_LEFT" -gt 0 ] && sleep "$SLEEP_LEFT" || true
  kill -0 "$LAUNCH_PID" 2>/dev/null || EARLY_EXIT=1
fi
OBS_END_EPOCH=$(python3 -c 'import time; print(f"{time.time():.3f}")')

# Terminate before wait — the EXIT trap's cleanup is the idempotent
# fallback for early/cancelled exits, but a normal end must not block on
# a still-running target.
cleanup_run
wait "$LAUNCH_PID" 2>/dev/null || true
exit 0
