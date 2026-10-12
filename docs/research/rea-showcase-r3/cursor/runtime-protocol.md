# Cursor runtime minimal closed loop — protocol

Objective (R3): connect, for one fixed version and one controlled setting
profile, the chain *file read → local event construction → queue/persist →
network destination* — or record a bounded, well-scoped negative/unknown.

## Hard boundaries (from task order)

- Synthetic history records only. No real user history is touched; the real
  `~/.claude`, `~/.codex` trees are never read by the test harness.
- No modification of switches to manufacture "default behavior" claims.
  Intervention variants are labeled `INTERVENTION:`.
- No system-level trust/pf/VPN changes without separate authorization —
  therefore **content-level MITM is out of scope this round**; L3 is limited
  to destination-level observation (process → remote host/port/volume) plus
  any plaintext metadata the OS exposes.
- `state.vscdb` access is read-only, scope-limited to
  `externalCliAnalytics.*` keys; the whole DB is never exported.

## Isolation design

- Fake `$HOME` (`/tmp/rea-r3/home-<ts>/`) containing only synthetic
  `~/.claude/history.jsonl` and `~/.codex/history.jsonl` canary records
  (unique sentinel strings, e.g. `REA_R3_CANARY_<n>`).
- Launch: `Cursor.app/Contents/MacOS/Cursor` with `HOME=<fake>`,
  `--user-data-dir=<fake>/cursor-data`. Node `os.homedir()` honors `HOME`;
  caveat recorded: if the telemetry path uses `pw_dir` instead of `HOME`,
  the probe yields a false negative — detect by checking which path the
  code reads (L1 trace informs this).
- Observation, no root required:
  - `lsof -p <pid>` snapshots + `lsof -i -P -n` for sockets
  - `nettop -p <pid>` or `netstat` deltas for destination-level L3
  - `sqlite3` (read-only URI `file:...?mode=ro`) for `state.vscdb` key
    check before/after
- Each run records: version/commit of the app, env overrides, start/end
  timestamps, observed file accesses to canary paths, queue-key deltas,
  destination list, and explicit unknowns.

## What this round can conclude at most

L2 correlation (Cursor process opened canary file / wrote queue key) and
L3-destination (which endpoints it connected to, when). It cannot conclude
field-level egress — that requires authorized MITM, deferred.
