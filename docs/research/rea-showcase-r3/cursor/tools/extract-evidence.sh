#!/bin/bash
# extract-evidence.sh — READ-ONLY extraction over a frozen run directory.
#
# Never launches the target, never writes into the run dir, never rewrites
# inputs. Output directory must not already exist and must NOT live inside
# the run dir being read (evidence packaging never touches its source).
# Synthetic inputs are COPIED into the package under inputs/ so the
# package is self-contained and portable; hashes.txt records package-
# relative paths only.
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
RUN_DIR=$(cd "$RUN_DIR" && pwd)
[ -f "$RUN_DIR/run-manifest.json" ] || { echo "no run-manifest.json in $RUN_DIR" >&2; exit 1; }
case "$(cd "$(dirname "$OUT_DIR")" && pwd)/$(basename "$OUT_DIR")" in
  "$RUN_DIR"/*) echo "refusing to write output inside the source run dir" >&2; exit 1 ;;
esac
[ ! -e "$OUT_DIR" ] || { echo "refusing to overwrite existing $OUT_DIR" >&2; exit 1; }
mkdir -p "$OUT_DIR/inputs"

D="$RUN_DIR/home/cursor-data"

# --- package the synthetic inputs (portable, package-relative) ---
for src in "$RUN_DIR/home/.claude/history.jsonl" "$RUN_DIR/home/.codex/history.jsonl"; do
  case "$src" in
    */.claude/*) cp "$src" "$OUT_DIR/inputs/claude-history.jsonl" ;;
    */.codex/*)  cp "$src" "$OUT_DIR/inputs/codex-history.jsonl" ;;
  esac
done
cp "$RUN_DIR/inputs-hashes.txt" "$OUT_DIR/inputs/source-hashes.txt" 2>/dev/null || true
cp "$RUN_DIR/run-manifest.json" "$OUT_DIR/run-manifest.json"

# --- scoped state.vscdb read (read-only, LIKE-scoped keys, full values) ---
DB="$D/User/globalStorage/state.vscdb"
if [ -f "$DB" ]; then
  sqlite3 "file:$DB?mode=ro" \
    "SELECT key||'|'||value FROM ItemTable WHERE key LIKE 'externalCliAnalytics%' OR key LIKE '%privacyMode%' OR key LIKE '%PrivacyMode%' OR key LIKE '%telemetry.%';" \
    > "$OUT_DIR/state-vscdb-scoped.txt"
else
  echo "state.vscdb absent" > "$OUT_DIR/state-vscdb-scoped.txt"
fi

# --- breadcrumb excerpts with source file + line number + byte offset ---
# Raw view: every matching record, duplicates preserved. Also emits a
# parse report so malformed log content cannot masquerade as zero events.
python3 - "$D" "$OUT_DIR" <<'PYEOF'
import glob, json, os, sys

d, out = sys.argv[1], sys.argv[2]
report = {"files_scanned": 0, "bytes_scanned": 0, "records_matched": 0,
          "files_with_errors": [], "missing_dir": False}
raw_path = os.path.join(out, "breadcrumbs-raw.txt")

logs = sorted(glob.glob(os.path.join(d, "logs", "*", "cursor-sentry-events.log")))
if not logs:
    report["missing_dir"] = True

def extract_json_objects(data: bytes):
    """Yield (offset, text) of top-level balanced {...} candidates on each line."""
    start = 0
    while True:
        nl = data.find(b"\n", start)
        if nl == -1:
            line, start = data[start:], len(data)
        else:
            line, start = data[start:nl], nl + 1
        i = 0
        while i < len(line):
            if line[i:i+1] == b"{":
                depth, j = 0, i
                while j < len(line):
                    if line[j:j+1] == b"{": depth += 1
                    elif line[j:j+1] == b"}":
                        depth -= 1
                        if depth == 0: break
                    j += 1
                if depth == 0:
                    yield line[i:j+1]
                    i = j + 1
                    continue
            i += 1
        if nl == -1: break

matches = []
for path in logs:
    report["files_scanned"] += 1
    try:
        data = open(path, "rb").read()
    except OSError as e:
        report["files_with_errors"].append(f"{path}: {e}")
        continue
    report["bytes_scanned"] += len(data)
    base = 0
    for obj in extract_json_objects(data):
        try:
            rec = json.loads(obj)
        except (ValueError, UnicodeDecodeError):
            continue
        if not isinstance(rec, dict):
            continue
        if rec.get("category") != "event":
            continue
        msg = rec.get("message", "")
        if not (msg.startswith("ex_hs") or msg.startswith("env_")):
            continue
        off = data.find(obj, base)
        line_no = data.count(b"\n", 0, off) + 1 if off >= 0 else 0
        matches.append((path, line_no, off, obj))
        base = off + 1
report["records_matched"] = len(matches)

with open(raw_path, "w") as o:
    for path, line_no, off, obj in matches:
        o.write(f"{path}:{line_no}:{off}: {obj.decode('utf-8', 'replace')}\n")

with open(os.path.join(out, "extract-report.json"), "w") as o:
    json.dump(report, o, indent=2)
PYEOF

# Deduped view: one line per unique record body.
awk -F': ' '{sub(/^[^:]+:[0-9]+:[0-9]+: /,""); print}' "$OUT_DIR/breadcrumbs-raw.txt" \
  | sort -u > "$OUT_DIR/breadcrumbs-deduped.txt"

# --- sentry egress queue snapshot (copy only if present) ---
if [ -f "$D/sentry/queue/queue-v2.json" ]; then
  cp "$D/sentry/queue/queue-v2.json" "$OUT_DIR/sentry-queue.json"
else
  echo "sentry queue absent" > "$OUT_DIR/sentry-queue.json"
fi

# --- hashes of everything in the package (excluding this file itself) ---
find "$OUT_DIR" -type f ! -name 'hashes.txt' -exec shasum -a 256 {} + \
  | sed "s|$OUT_DIR/||" > "$OUT_DIR/hashes.txt"

echo "evidence extracted: $OUT_DIR"
