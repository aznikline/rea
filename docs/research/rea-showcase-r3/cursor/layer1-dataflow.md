# Cursor `externalCliAnalytics` — L1 static dataflow trace

Scope: five preserved builds (3.14.7, 3.20.21, 3.23.23, 3.24.9, 3.24.12),
`Cursor.app/Contents/Resources/app/out/vs/workbench/workbench.desktop.main.js`.
All offsets are byte offsets in that file. Method: marker offset location
(`grep -bo`), ±byte-window extraction, semantic-literal cross-version
comparison (raw span SHA-256s differ by minifier renaming — expected).

Reference runtime anchors (L2, `layer2-runtime-results.md`): canary
`sessionId`/`ts` propagated byte-exact; `n`=entry text length; ~90 s
post-launch firing; `env_ac`/`env_cx`/`env_gl` companion events;
`externalCliAnalytics.lastTimestamp.*` persisted in `state.vscdb`.

## The contribution (3.24.12, offsets 31178300–31181054)

Class `uWn`, registered as `workbench.contrib.externalCliAnalytics`,
lifecycle `cs.Eventually` (runs once workbench startup completes — matches
the observed ~90 s first firing).

### Stage table

| Stage | Evidence (3.24.12 offset) | Detail |
|---|---|---|
| Registration | `uWn.ID="workbench.contrib.externalCliAnalytics"`, `ts(uWn.ID,uWn,cs.Eventually)` ~31181054 | workbench contribution, DI-injected |
| Trigger — immediate | `this._poll()` in constructor ~31178560 | fires at activation, not only hourly |
| Trigger — repeat | `cronService.registerTask({id:"external-cli-analytics-poll", intervalMs:3600*1e3})` ~31178900 | hourly |
| Gate | `this.experimentService.checkFeatureGate("enable_ex_hs",{disableExposureLog:!1})` ~31179119 | exposure logging **enabled**; flag registry literal `enable_ex_hs:{client:!0,default:!0}` at 15494396 → **default ON** |
| Home resolution | `await this.pathService.userHome()` | VS Code pathService → OS home; consistent with the successful `HOME`-env redirect at runtime |
| File 1 | `joinPath(home,".claude","history.jsonl")` ~31179427 | JSONL, fields `timestamp`(ms), `sessionId`, `display`, `project` |
| File 2 | `joinPath(home,".codex","history.jsonl")` ~31180089 | JSONL, fields `ts`(sec, ×1e3), `session_id`, `text` |
| File 3 (extra) | `joinPath(home,".claude","projects",<dashed-proj>,"sessions-index.json")` | per-project session→messageCount index; project dir name = path with `/\`→`-` |
| Event | `analyticsService.trackEvent("ex_hs2",{tool:"ac",ts,sessionId,n:display.length,msgCount})` / `{tool:"cx",ts,session_id,n:text.length}` ~31179821/31180373 | `n` = **text length only**; `sessionId` verbatim; `msgCount` claude-only |
| Bookmark | `storageService.store("externalCliAnalytics.lastTimestamp.claude"/".codex", ts, 0, 1)` ~31178571–31178640 | profile-scope storage → `User/globalStorage/state.vscdb`; only entries **newer** than bookmark are emitted |
| Send path | `trackEvent` on injected `analyticsService` | drains into the telemetry pipeline; observed locally as `category:"event"` breadcrumbs in `cursor-sentry-events.log`; actual wire egress = L3 UNKNOWN |

### `env_*` companion — a different contribution

`workbench.contrib.pathInspection` (offset 39700500+):
`EXECUTABLES_TO_CHECK=[{codex→env_cx},{claude→env_ac},{amp→env_az},{gemini→env_gl},{agent→env_agent}]`,
`APPLICATIONS_TO_CHECK=[{Antigravity→env_ag}]`. Each fires an event when
`pathInspectionService.checkApplicationExists(<name>)` succeeds — i.e.
**detection of competitor tools installed on the machine** (exec presence,
not history files). Runtime `env_gl` fired without a gemini canary file —
consistent with executable-presence probing.

## Cross-version comparison (semantic literals in traced span)

| Token | 3.14.7 | 3.20.21 | 3.23.23 | 3.24.9 | 3.24.12 |
|---|---|---|---|---|---|
| `ex_hs2` | 2 | 2 | 2 | 2 | 2 |
| `tool:"ac"`/`tool:"cx"` | ✓/✓ | ✓/✓ | ✓/✓ | ✓/✓ | ✓/✓ |
| `msgCount` | ✓ | ✓ | ✓ | ✓ | ✓ |
| `3600*1e3` + `checkFeatureGate` + `disableExposureLog` | ✓ | ✓ | ✓ | ✓ | ✓ |
| `enable_ex_hs:{client:!0,default:!0}` (flag registry) | ✓ | ✓ | ✓ | ✓ | ✓ |
| `EXECUTABLES_TO_CHECK` list | identical | — | — | — | identical |

Verdict: the contribution is **semantically stable** across 3.14.7→3.24.12
within the examined spans. Earliest observed = 3.14.7; first-introduction
version remains UNKNOWN (earlier builds not fetched). The forum post's
implicit "new in 3.24.9" framing is not supported.

## What static analysis cannot establish (UNKNOWN)

- Server-side flag state per account/segment (`checkFeatureGate` default is
  true, remote override semantics unknown).
- Whether `analyticsService` itself has additional gates (e.g. telemetry
  level, privacy mode) before wire send — the pipeline internals need
  further tracing; runtime shows queuing under `privacyMode=true`.
- Field population under logged-in/upgraded profiles.
- Wire format/endpoint of the event — L3 unknown pending authorized capture.
- Whether `pathService.userHome()` consults anything beyond `HOME` in
  sandboxed/package-managed installs.

## Suggested next probes

- L2: does `enable_ex_hs` remote-off actually suppress (requires account or
  flagged offline flag override — intervention-labeled).
- L2: does `telemetry.telemetryLevel`/`privacyMode` toggling change
  enqueue behavior (intervention runs, separately labeled).
- L1: trace `analyticsService`/`trackEvent` drain path to endpoint name.
- L3: authorized MITM for field-level egress.
