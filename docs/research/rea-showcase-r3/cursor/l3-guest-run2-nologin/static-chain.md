# Static chain source pin — R3.6 additions

New static claims involve `main.js` and `product.json`, which are NOT
covered by the Mach-O + workbench dual-pin. All three files are pinned
here.

| file | sha256 | bytes |
|---|---|---|
| `Contents/MacOS/Cursor` (Mach-O) | `71e8dfc19ff2216a277315972dcca0ea83773e8ec214f3cf352ee9591ce38037` | — |
| `out/vs/workbench/workbench.desktop.main.js` | `044ce0931100af5fe95403e9a692b02932bc3e13a6763f576b851f503fefa518` | 39,801,012 |
| `out/main.js` | `15ffddb5737a90ee617a2e76e0e8d66ce49e752bedda1d95672562cd45da32bc` | 2,766,106 |
| `product.json` | `883fbb6afd62fc8f5defb3a29a4897a710093bac686cc4297fb7959413ffb211` | 52,411 |

## Anchored claims (byte offsets, verbatim anchors)

### `externalCliAnalytics` contribution → event (workbench JS)

- `uWn=class extends we{constructor` @ 31178661 — contribution class;
  constructor calls `this._poll()` and registers cron
  `external-cli-analytics-poll` @ 31178932 (`intervalMs:3600*1e3`).
- `checkFeatureGate("enable_ex_hs"` @ 31179101 — the only gate inside
  `_poll`, with `disableExposureLog:!1`.
- `trackEvent("ex_hs2"` @ 31179809 — inside `_processClaudeHistory`,
  fields `{tool:"ac",ts,sessionId,n,msgCount}`; codex twin uses
  `tool:"cx"` with `session_id`/`text` fields.
- `enable_ex_hs:{client:!0,default:!0}` @ 15494396 — flag registry
  entry; compiled default is true.

### Mirror log + envelope gating (main.js)

- `_isLegacyPrivacyMode===!0` guard precedes the mirror write call
  @ 1988084–1991087 region.
- `cursor-sentry-events.log` @ 1991560 — filename inside
  `_writeSentryEventToMirror`, created lazily under
  `environmentService.logsHome`; invoked only from the legacy-privacy
  branch of the envelope path.
- `_internalSendEnvelope(e){if(this._privateInferenceLockdown` @
  1992862 — early return when lockdown !== "disabled".
- `_shouldDropEvent(e,t){if(this._privateInfer` @ 1991861 — drops on
  lockdown, `event.process==="unknown"`, dedupe, legacy-privacy
  non-fatal.

### Egress endpoint config (product.json)

- `statsigClientKey` @ 1167 → `client-Bm4HJ0aDjXHQVsoACMREyLNxm5p6zzuzhO50MgtoT5D`
- `statsigLogEventProxyUrl` @ 1243 → `https://api3.cursor.sh/tev1/v1`

## Chain summary (static only — not runtime fact)

```text
uWn (Eventually phase, ctor + 1h cron)
  → _poll(): gate checkFeatureGate("enable_ex_hs") [default true]
  → read ~/.claude|codex/history.jsonl, filter ts > lastTimestamp
  → analyticsService.trackEvent("ex_hs2", {tool,ts,sessionId,n,msgCount})
  → statsig enqueue → proxy URL api3.cursor.sh/tev1/v1 (config constant)
  → (Sentry mirror log applies only to legacy-privacy Sentry envelopes,
     unrelated sink)
```

Config constants ≠ actual egress; observed runs show no api3 attempt.
