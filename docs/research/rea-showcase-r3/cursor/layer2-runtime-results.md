# Cursor Layer-2 runtime minimal closed loop — results

Run identity: **R3-CUR-RUN-1**.

- App: `Cursor.app` 3.24.12, commit `37b865941ccb31e2fc90c685157534efca87f964`,
  Electron 42.10.0, artifact `Cursor-3.24.12-darwin-arm64.dmg`
  SHA-256 `c5ed7193…f5f` (local-computed).
- Environment: isolated `HOME=/tmp/rea-r3/home-1791791263`,
  `--user-data-dir` inside fake home, fresh profile, **no account/login**,
  **default settings** (no intervention; this is a default-behavior run).
- Window: process start 2026-10-12 **07:47:53.061 UTC** (15:47:53 UTC+8,
  host TZ `Asia/Shanghai`) → kill ~15:52 local, ~5 min total.
- Host: macOS 27.0.1 arm64. Network routed via system VPN (fake-IP NAT,
  198.18.0.0/16) — real destination IPs unrecoverable from lsof; this limits
  L3 to connection-level observation.

**Timing correction (R3.1):** the `ex_hs2` breadcrumbs carry epoch
`1791791297.162` = **07:48:17.162 UTC** = 15:48:17 UTC+8, i.e.
**~24.1 s after process start** — not "~90 s" as an earlier draft stated.
All references below use the corrected value.

## Synthetic canary inputs (sole contents of fake home)

- `~/.claude/history.jsonl`: `{"display":"REA_R3_CANARY_CLAUDE_1 synthetic entry alpha","timestamp":1791787663000,"project":"/tmp/rea-r3","sessionId":"rea-r3-canary-claude"}` — text field 44 chars
- `~/.codex/history.jsonl`: `{"session_id":"rea-r3-canary-codex","ts":1791789463,"text":"REA_R3_CANARY_CODEX_1 synthetic entry beta"}` — text field 42 chars

## Observed (L2, local runtime)

1. **Both canary history files were read.** Proof by data propagation: the
   exact canary `sessionId` sentinels and timestamps appear inside
   constructed events (below). Direct `lsof` file-handle snapshots during a
   short poll window did not catch the read — reads are transient; the
   propagation chain is the positive evidence.
2. **Events constructed ~24.1 s after process start** (breadcrumb epoch
   `1791791297.162` = 07:48:17.162 UTC vs `app_start_time`
   07:47:53.061 UTC), recorded in
   `cursor-data/logs/<ts>/cursor-sentry-events.log` as telemetry-pipeline
   breadcrumbs:

   ```
   "ex_hs2" {"tool":"cx","ts":1791789463000,"sessionId":"rea-r3-canary-codex","n":42}
   "ex_hs2" {"tool":"ac","ts":1791787663000,"sessionId":"rea-r3-canary-claude","n":44}
   ```

   Note (R3.2 review): the raw `ex_hs2-breadcrumbs.txt` excerpt contains
   these two records **twice each** — the log writes the same breadcrumb
   into two places/rotations. Raw records ≠ distinct events; only the two
   deduplicated records above are counted. The R3.2 tools
   (`tools/extract-evidence.sh`, `tools/verify-evidence.sh`) now emit
   `breadcrumbs-raw.txt` (source file:line:offset, duplicates preserved)
   and `breadcrumbs-deduped.txt` separately so this cannot be miscounted.

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
5. **Local privacy-state keys in this fresh profile** (scoped query):
   `cursorai/donotchange/privacyMode = true`,
   `newPrivacyMode2 = {"privacyMode":"PRIVACY_MODE_NO_STORAGE"}`. The
   externalCliAnalytics read/queue path was observed executing while these
   stored values were present at query time. **This is a
   this-environment/local-state observation only** — it does not establish
   when the keys were written relative to the reads, whether a logged-in or
   upgraded profile carries the same values, or any account-level or
   server-side privacy-policy outcome.
6. Trigger cadence: first poll fired ~24.1 s after process start in this
   run — i.e., a startup/near-startup execution exists (L1 confirms an
   immediate `_poll()` at construction plus the hourly cron; the
   Eventually-lifecycle activation explains the short post-start delay).
   The hourly cadence in forum reports is the *repeat* interval.

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

Committed (sanitized, canary-only) under `cursor/evidence/`:
`claude-history.jsonl`, `codex-history.jsonl` (synthetic inputs),
`ex_hs2-breadcrumbs.txt` (canary-scoped telemetry log excerpt),
`state-vscdb-scoped.txt` (LIKE-scoped read-only sqlite output),
`sentry-queue.json` (empty queue snapshot), `extract.sh` (exact commands
with run ID and corrected timing math), `hashes.txt` (SHA-256 of each).
Full fake-home tree retained locally at `/tmp/rea-r3/home-1791791263/`;
not committed (contains runtime-generated profile internals).

## Review status (R3.1)

- RUN_STATUS: executed once, bounded ~5 min window, single version.
- OBSERVATION_STATUS: L2 positive for read→construct→queue→bookmark chain
  in this environment; L3 content egress UNKNOWN.
- REVIEW_STATUS: awaiting independent review — raw excerpts now committed
  so the propagation chain (canary → event → bookmark) is checkable
  without rerunning.
