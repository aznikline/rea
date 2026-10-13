# L3 guest run 2 — R3.6 no-login activation & coverage matrix

Date: 2026-10-13 (all times UTC). Guest: `rea-l3-vm`, macOS 15.7.7
arm64 (Tart/Virtualization.framework). Frozen program baseline:
`02a7204535d2af60648ffc02b03a8364faeac8b2`; frozen runner script
sha256 `7685271a…aa2e` (repo == guest-deployed copy).

Target identity for every run: Mach-O sha256
`71e8dfc1…038037` and workbench.desktop.main.js sha256
`044ce093…fefa518` — both `match` in every manifest.

## Diagnostic instrumentation added for this round (uniform across U0–U2g)

- `--log-net-log=/Users/admin/l3/netlog-<cond>.json` on the target —
  marked diagnostic intervention; NetLog content is network-stack
  metadata, not field-level egress evidence.
- `lsof -nP -i -c Cursor` socket sampler, 5 s cadence, into
  `~/l3/conns-<cond>.log`.
- Same mitmdump capture path (`127.0.0.1:8888`, system proxy retained
  from R3.5, `RETAINED_FOR_EXPERIMENT`).
- No login, no QUIC disable, no proxy change, no target modification.

## Matrix

| cond | run id | delta vs previous | launch context | ready | obs window | verdict |
|---|---|---|---|---|---|---|
| U0 | `run-1791882586-876` | baseline (empty window, canary history) | SSH-launched | 1 (15.3 s) | 225.0 s | PASS/VALID/NOT_OBSERVED/ELIGIBLE |
| U1 | `run-1791884333-1354` | + open `~/l3/synth-proj` folder | SSH-launched | 0* | 240 s | PASS/QUALIFIED/NOT_OBSERVED/NO |
| U2 | `run-1791884745-1853` | + Agent panel via Cmd+I | SSH-launched | 0* | 240 s | PASS/QUALIFIED/NOT_OBSERVED/NO |
| U2g | `run-1791885583-2605` | U2 retried under GUI-session launch | `launchctl asuser 501` | 0* | 240 s | PASS/QUALIFIED/NOT_OBSERVED/NO |

\* Folder windows log to `window1/` (not `window*_wb*/`), so the
harness readiness detector missed them even though renderer.log shows
a loaded workbench (83 lines). Detector artifact, recorded as
`workbench_readiness_not_reached` — readiness *flag* is a harness
signal, not a target property.

### U2 / U2g Agent-panel caveat

- U2 (SSH launch): window never appeared on-screen in the console
  session; `CGEventPostToPid` Cmd+I delivered but panel-open state is
  **unverified**; injection also landed near window end.
- U2g (asuser-501 launch): real L0 window on-screen
  (`CGWindowList: Cursor L0 0,25 1024x686`), app activated
  (`activateWithOptions=1`), Cmd+I injected twice within the window.
  Panel-open state still **not screenshot-verified** — `screencapture`
  lacks Screen Recording TCC so captures show wallpaper only. No
  login prompt or SecurityAgent dialog was listed on-screen during or
  after injection.

## Findings

### Local observations (all four runs)

- `cursor-sentry-events.log` absent everywhere — consistent with the
  static finding that this file is written **only when
  `_isLegacyPrivacyMode === true`** (main.js `_writeSentryEventToMirror`
  is called under the legacy-privacy branch). Its absence carries
  almost no information in default mode; telemetry events take a
  different path.
- `state.vscdb`: no `externalCliAnalytics.lastTimestamp.*` keys, no
  statsig bootstrap cache; Local Storage leveldb essentially empty.
- `telemetry.log` empty in all runs; `composer.log` empty.
- renderer.log shows `cursor_agent_host gate is disabled`,
  `agentHostEnabled=false`, `PushRequestContextService ... disabled`.

### Network observations

- Proxy-captured target flows: U0 `api2.cursor.sh /extensions-control`
  ×1; U1 same ×1 (+5 system flows); U2 same ×1; U2g **none** (netlog
  shows an api2 connection attempt, no completed flow).
- Zero canary/run-id/`ex_hs2`/`api3.cursor.sh`/`/tev1/` bytes in any
  capture (container-byte search, receipt in `network/`).
- lsof cross-check: zero direct-egress TCP and zero UDP sockets owned
  by Cursor in any sample — the only persistent socket is the loopback
  connection to the proxy. QUIC bypass not observed (bounded by 5 s
  cadence).
- NetLog (truncated at last flush ≈ launch phase): api2.cursor.sh
  only; every remote attempt resolves to `127.0.0.1:8888`.

### Static chain (workbench.desktop.main.js + main.js @3.24.12)

`externalCliAnalytics` (`uWn`, `workbench.contrib.*`, phase
`Eventually`): constructor calls `_poll()` once immediately + hourly
cron. `_poll` gates on
`experimentService.checkFeatureGate("enable_ex_hs")` whose compiled
default is **`true`** (feature-gate table `default:true`). If the gate
passes it reads `~/.claude/history.jsonl` and `~/.codex/history.jsonl`
(our isolated HOME was populated), filters `ts > lastTimestamp`,
and calls `analyticsService.trackEvent("ex_hs2", {tool, ts, sessionId,
n})`. Statsig events egress via `statsigLogEventProxyUrl =
https://api3.cursor.sh/tev1/v1` — a different host than the observed
api2.

So in-window non-observation is consistent with any of:
(a) `checkFeatureGate` returned false (statsig SDK may not have
initialized — no bootstrap cache, no statsig CDN requests observed);
(b) the contribution's first `_poll` did not fire before SIGKILL or
its storage write never flushed;
(c) events were enqueued but the statsig batcher never flushed in
window;
(d) `_isEgressPolicyPending` held egress until a policy decision that
never arrived. Local artifacts do not disambiguate; **"must log in"
is not demonstrated**.

## R3.5 correction carried into this round

- R0 manifest wall-clock 6010.8 s was inflated by guest suspend/resume
  (flow-timestamp gaps 06:31→07:15→07:47→08:09 UTC); active runtime
  ≈ standard 240 s. R0 excluded from equal-window comparison.
- `capture-r0.mitm` is mixed-provenance (aborted r0 + r0b); its two
  api2 flows belong to the aborted attempt.
- `ELIGIBLE_FOR_COMPARISON` scoped to packaged-observation methodology,
  not full outbound coverage.

## Conclusion (bounded)

Within the no-login scope — empty window, synthetic project folder,
Agent panel attempt — the target produced at most a single
`api2.cursor.sh/extensions-control` request per run and no captured or
socket-level egress carrying canary/session markers. Closing statement
per protocol: **the ex_hs2-triggering egress was not observed within
this scope**; no-login conditions are now complete. Whether
authentication is a prerequisite is still unproven — the gate chain
offers at least four non-auth explanations above. A dedicated research
account is the next experiment dimension IF pursued, requiring
separate authorization.

## Artifacts

- `runs/*-run-manifest.json` — per-run manifests (frozen, unedited)
- `evidence-u0|u1|u2|u2g/` — extracted evidence packages + verifier
  output recorded above
- `network/flows-*.json` — sanitized flow manifests (target flows
  verbatim; non-target system flows reduced to host+count)
- `network/capture-register.md`, `conns-summary.md`,
  `canary-search-receipt.md`
- `tools/run-u.sh` (orchestrator), `flow-manifest.py`,
  `sanitize-manifests.py`
- raw `.mitm`: guest `~/l3/` + host `/tmp/rea-r32/captures/`
  (hash-verified, not committed)

Environment state: guest CA + proxy **RETAINED_FOR_EXPERIMENT**; host
trust/proxy/pf/VPN untouched.
