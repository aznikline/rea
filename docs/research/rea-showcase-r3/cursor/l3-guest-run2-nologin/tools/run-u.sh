#!/bin/zsh
# R3.6 U-condition orchestrator. usage: run-u.sh u0|u1|u2
set -e
COND=$1
L3=/Users/admin/l3
CURSOR_SHA=71e8dfc19ff2216a277315972dcca0ea83773e8ec214f3cf352ee9591ce38037
WB_SHA=044ce0931100af5fe95403e9a692b02932bc3e13a6763f576b851f503fefa518

AVAIL=$(df -g / | tail -1 | awk "{print \$4}")
if [ "$AVAIL" -lt 8 ]; then echo "GUEST_DISK_LOW ${AVAIL}Gi"; exit 2; fi

pkill -f "mitmdump" 2>/dev/null || true; sleep 1
rm -f "$L3/capture-${COND}.mitm" "$L3/netlog-${COND}.json" "$L3/conns-${COND}.log"

$L3/mitmproxy.app/Contents/MacOS/mitmdump -w "$L3/capture-${COND}.mitm" \
  --listen-port 8888 --set flow_detail=3 > "$L3/mitmdump-${COND}.log" 2>&1 &
sleep 3

( while true; do
    echo "--- $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    lsof -nP -i -c Cursor 2>/dev/null
    sleep 5
  done ) > "$L3/conns-${COND}.log" 2>&1 &
SAMPLER=$!

RC=0
EXTRA=(--extra-arg "--log-net-log=$L3/netlog-${COND}.json")
if [ "$COND" != "u0" ]; then
  EXTRA+=(--extra-arg "$L3/synth-proj")
fi

$L3/tools/run-experiment.sh --history canary --duration 240 \
  --runs-root "$L3/runs" \
  --cursor-app "$L3/Cursor.app/Contents/MacOS/Cursor" \
  --expect-sha256 "$CURSOR_SHA" \
  --expect-workbench-sha256 "$WB_SHA" \
  "${EXTRA[@]}" || RC=$?

kill $SAMPLER 2>/dev/null || true
pkill -f "mitmdump.*capture-${COND}" 2>/dev/null || true
echo "RUN_DONE rc=$RC cond=$COND"
exit $RC
