#!/bin/bash
# REA-R3 Cursor L2 evidence extraction — exact commands used.
# Run 1 identity: Cursor 3.24.12 (commit 37b865941ccb31e2fc90c685157534efca87f964),
# dmg sha256 c5ed7193bfb906e2aae3f3f281c62cb979efd1b662c73524a15f1c4448734f5f.
# FH = isolated fake HOME = /tmp/rea-r3/home-1791791263
# Times: app launch logged 2026-10-12T07:47:53.061Z (UTC) = 15:47:53 UTC+8.
# Event breadcrumb timestamp 1791791297.162 (epoch) = 07:48:17.162 UTC
# = 15:48:17 UTC+8 => ~24.1 s after app start, NOT ~90 s (corrected R3.1).

set -euo pipefail
FH=/tmp/rea-r3/home-1791791263
D="$FH/cursor-data"

# --- synthetic inputs (created before launch; hashes in hashes.txt) ---
mkdir -p "$FH/.claude" "$FH/.codex" "$FH/cursor-data"
# claude: timestamp is milliseconds, sessionId, display (44-char text)
printf '%s\n' '{"display":"REA_R3_CANARY_CLAUDE_1 synthetic entry alpha","timestamp":1791787663000,"project":"/tmp/rea-r3","sessionId":"rea-r3-canary-claude"}' > "$FH/.claude/history.jsonl"
# codex: ts is SECONDS, session_id, text (42-char text)
printf '%s\n' '{"session_id":"rea-r3-canary-codex","ts":1791789463,"text":"REA_R3_CANARY_CODEX_1 synthetic entry beta"}' > "$FH/.codex/history.jsonl"

# --- launch (default settings, no login, no intervention) ---
env HOME="$FH" XDG_CONFIG_HOME="$FH/.config" \
  "/Users/wizout/op/targets/cursor/cursor-3.24.12/Cursor.app/Contents/MacOS/Cursor" \
  --user-data-dir="$FH/cursor-data" --disable-crash-reporter \
  > "$FH/launch.log" 2>&1 &

# --- scoped state.vscdb read (read-only, LIKE-scoped keys only) ---
sqlite3 "file:$D/User/globalStorage/state.vscdb?mode=ro" \
  "SELECT key,substr(value,1,200) FROM ItemTable WHERE key LIKE 'externalCliAnalytics%' OR key LIKE '%privacyMode%' OR key LIKE '%PrivacyMode%' OR key LIKE '%telemetry.%';" \
  > state-vscdb-scoped.txt

# --- telemetry breadcrumb excerpt (canary-scoped only) ---
grep -o '{"timestamp":[0-9.]*,"category":"event","message":"ex_hs[0-9]*","data":{[^}]*}}' \
  "$D"/logs/*/cursor-sentry-events.log > ex_hs2-breadcrumbs.txt
grep -o '"message":"env_[a-z]*","data":{[^}]*}' \
  "$D"/logs/*/cursor-sentry-events.log | sort -u >> ex_hs2-breadcrumbs.txt

# --- sentry egress queue snapshot ---
cp "$D/sentry/queue/queue-v2.json" sentry-queue.json

# --- file hashes ---
shasum -a 256 claude-history.jsonl codex-history.jsonl ex_hs2-breadcrumbs.txt \
  state-vscdb-scoped.txt sentry-queue.json > hashes.txt
