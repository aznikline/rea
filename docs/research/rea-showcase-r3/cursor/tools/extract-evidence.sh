#!/bin/bash
# extract-evidence.sh — READ-ONLY extraction over a frozen run directory.
#
# Never launches the target, never writes into the run dir, never rewrites
# inputs. Output directory must not already exist (no overwrite of frozen
# evidence). Excerpts carry source file + byte offset; raw (with duplicate
# breadcrumb records) and deduplicated views are separate files.
#
# Usage: extract-evidence.sh --run RUN_DIR --out OUT_DIR

set -euo pipefail

RUN_DIR=""
OUT_DIR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --run) RUN_DIR=$2; shift 2 ;;
    --out) OUT_DIR=$2; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done
[ -n "$RUN_DIR" ] && [ -n "$OUT_DIR" ] || { echo "usage: extract-evidence.sh --run RUN_DIR --out OUT_DIR" >&2; exit 2; }
[ -f "$RUN_DIR/run-manifest.json" ] || { echo "no run-manifest.json in $RUN_DIR" >&2; exit 1; }
[ ! -e "$OUT_DIR" ] || { echo "refusing to overwrite existing $OUT_DIR" >&2; exit 1; }
mkdir -p "$OUT_DIR"

D="$RUN_DIR/home/cursor-data"

# --- scoped state.vscdb read (read-only, LIKE-scoped keys, full values) ---
DB="$D/User/globalStorage/state.vscdb"
if [ -f "$DB" ]; then
  sqlite3 "file:$DB?mode=ro" \
    "SELECT key,value FROM ItemTable WHERE key LIKE 'externalCliAnalytics%' OR key LIKE '%privacyMode%' OR key LIKE '%PrivacyMode%' OR key LIKE '%telemetry.%';" \
    > "$OUT_DIR/state-vscdb-scoped.txt"
else
  echo "state.vscdb absent" > "$OUT_DIR/state-vscdb-scoped.txt"
fi

# --- breadcrumb excerpts with source file + line number + byte offset ---
# Raw view: every matching record, duplicates preserved.
python3 - "$D" "$OUT_DIR/breadcrumbs-raw.txt" <<'PYEOF'
import glob, os, re, sys
d, out = sys.argv[1], sys.argv[2]
pat = re.compile(rb'\{"timestamp":[0-9.]*,"category":"event","message":"(?:ex_hs[0-9]*|env_[a-z]+)","data":\{[^}]*\}\}')
with open(out, "w") as o:
    for path in sorted(glob.glob(os.path.join(d, "logs", "*", "cursor-sentry-events.log"))):
        with open(path, "rb") as f:
            data = f.read()
        for m in pat.finditer(data):
            line_no = data.count(b"\n", 0, m.start()) + 1
            o.write(f"{path}:{line_no}:{m.start()}: {m.group(0).decode('utf-8', 'replace')}\n")
PYEOF

# Deduped view: same records, one line per unique record body.
awk -F': ' '{sub(/^[^:]+:[0-9]+:[0-9]+: /,""); print}' "$OUT_DIR/breadcrumbs-raw.txt" \
  | sort -u > "$OUT_DIR/breadcrumbs-deduped.txt"

# --- sentry egress queue snapshot (copy only if present) ---
if [ -f "$D/sentry/queue/queue-v2.json" ]; then
  cp "$D/sentry/queue/queue-v2.json" "$OUT_DIR/sentry-queue.json"
else
  echo "sentry queue absent" > "$OUT_DIR/sentry-queue.json"
fi

cp "$RUN_DIR/run-manifest.json" "$OUT_DIR/run-manifest.json"

# --- hashes of produced evidence (excluding this file itself) and the
# synthetic inputs, recorded with run-relative paths to avoid basename
# collisions (.claude/history.jsonl vs .codex/history.jsonl) ---
{
  find "$OUT_DIR" -maxdepth 1 -type f ! -name 'hashes.txt' -exec shasum -a 256 {} + | sed "s|$OUT_DIR/||"
  shasum -a 256 "$RUN_DIR/home/.claude/history.jsonl" "$RUN_DIR/home/.codex/history.jsonl" 2>/dev/null || true
} > "$OUT_DIR/hashes.txt"

echo "evidence extracted: $OUT_DIR"
