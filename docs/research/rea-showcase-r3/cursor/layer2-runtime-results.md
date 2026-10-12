# Cursor Layer-2 runtime minimal closed loop — results

Run identity:

- App: `Cursor.app` 3.24.12, commit `37b865941ccb31e2fc90c685157534efca87f964`,
  Electron 42.10.0, artifact `Cursor-3.24.12-darwin-arm64.dmg`
  SHA-256 `c5ed7193…f5f` (local-computed).
- Environment: isolated `HOME=/tmp/rea-r3/home-1791791263`,
  `--user-data-dir` inside fake home, fresh profile, **no account/login**,
  **default settings** (no intervention; this is a default-behavior run).
- Window: launch 15:47:53 → kill ~15:52, ~5 min total.
- Host: macOS 27.0.1 arm64. Network routed via system VPN (fake-IP NAT,
  198.18.0.0/16) — real destination IPs unrecoverable from lsof; this limits
  L3 to connection-level observation.

## Synthetic canary inputs (sole contents of fake home)

- `~/.claude/history.jsonl`: `{"display":"REA_R3_CANARY_CLAUDE_1 synthetic entry alpha","timestamp":1791787663000,"project":"/tmp/rea-r3","sessionId":"rea-r3-canary-claude"}` — text field 44 chars
- `~/.codex/history.jsonl`: `{"session_id":"rea-r3-canary-codex","ts":1791789463,"text":"REA_R3_CANARY_CODEX_1 synthetic entry beta"}` — text field 42 chars

## Observed (L2, local runtime)

1. **Both canary history files were read.** Proof by data propagation: the
   exact canary `sessionId` sentinels and timestamps appear inside
   constructed events (below). Direct `lsof` file-handle snapshots during a
   short poll window did not catch the read — reads are transient; the
   propagation chain is the positive evidence.
2. **Events constructed ~90 s after launch** (breadcrumb timestamps
   1791791297 vs app_start 15:47:53), recorded in
   `cursor-data/logs/<ts>/cursor-sentry-events.log` as telemetry-pipeline
   breadcrumbs:

   ```
   "ex_hs2" {"tool":"cx","ts":1791789463000,"sessionId":"rea-r3-canary-codex","n":42}
   "ex_hs2" {"tool":"ac","ts":1791787663000,"sessionId":"rea-r3-canary-claude","n":44}
   ```

   Field mapping (observed, not claimed universal): `tool` codes `ac`/`cx`
   for claude/codex sources; `ts` = entry timestamp (ms); `sessionId` =
   **verbatim** session identifier from the history file; `n` = **character
   count of the entry text** (42/44 exact match). Entry text itself was NOT
   observed in the event.
3. **Companion `env_*` probe events** fired: `env_ac`, `env_cx`, `env_gl`
   (source_process renderer, empty data in the breadcrumb) — consistent with
   per-external-tool environment probing. `env_gl` has no counterpart canary
   (no `~/.gemini` file was planted); its field meaning is UNKNOWN.
4. **Progress bookmarks persisted** in
   `cursor-data/User/globalStorage/state.vscdb` (scoped read-only query):
   `externalCliAnalytics.lastTimestamp.claude = 1791787663000`,
   `.codex = 1791789463000` — exactly the canary timestamps, i.e. the tool
   bookmarks per-source read progress.
5. **Privacy mode state in this fresh default profile**:
   `cursorai/donotchange/privacyMode = true`,
   `newPrivacyMode2 = {"privacyMode":"PRIVACY_MODE_NO_STORAGE"}`. The
   externalCliAnalytics read/queue pipeline ran **under this state**.
   (Caveat: fresh-profile `privacyMode=true` may reflect a different default
   than an upgraded logged-in profile — treat as this-environment fact, not
   a universal default.)
6. Trigger cadence: first poll fired ~90 s after launch in this run —
   i.e., a startup/near-startup execution exists; the hourly cadence claimed
   in forum reports is a *repeat* interval, not the only trigger. L1 trace
   will pin the exact schedule.

## Observed (L3, destination-level only)

- ~24 ESTABLISHED TCP connections to fake-IP endpoints on :443 plus QUIC/UDP
  flows from the test instance during the window (hosts masked by VPN
  fake-IP; hostnames not recoverable — recorded limitation).
- `cursor-data/sentry/queue/queue-v2.json` was empty `[]` at snapshot —
  consistent with either already-flushed envelopes or breadcrumbs traveling
  inside error envelopes. **Cannot distinguish.**

## Explicitly NOT established

- Whether `ex_hs2` event bytes left the machine (content-level egress needs
  authorized MITM — out of scope, system trust untouched).
- Server-side storage, retention, or use.
- Whether logged-in/upgraded profiles behave identically.
- Field mapping for `env_*` events beyond name presence.
- Behavior of versions other than 3.24.12 (L1 markers exist in 3.23.23 and
  3.24.9; runtime equivalence unverified).

## Evidence preservation

Sanitized scoped extracts only (canary strings, no real user data):
`/tmp/rea-r3/home-1791791263/evidence/` —
`history.jsonl`×2, `ex_hs2-breadcrumbs.txt`, `state-vscdb-scoped.txt`,
`sentry-queue.json`. Full fake-home tree retained locally for re-inspection;
not committed (contains runtime-generated profile internals).
