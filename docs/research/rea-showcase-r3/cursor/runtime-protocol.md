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

## Verdict contract (R3.4)

The pipeline is `run-experiment.sh` → `extract-evidence.sh` →
`verify-evidence.sh`. The verifier emits four independent axes:

- `EVIDENCE_INTEGRITY` — PASS/FAIL. Requires: all required files present,
  every on-disk package file covered by `hashes.txt` (paths
  package-relative, no escape), packaged inputs parse AND agree with the
  manifest's claimed sessionIds/timestamps, no extractor file errors, and
  zero `unparsed_candidates` (a record carrying an event marker that
  failed to parse fails integrity — it cannot masquerade as zero events).
- `RUN_VALIDITY` — VALID / QUALIFIED / INVALID. INVALID = early exit.
  QUALIFIED = readiness basis not reached.
- `OBSERVATION` — OBSERVED / OBSERVED_PARTIAL / FIELD_MISMATCH /
  NOT_OBSERVED_WITHIN_WINDOW / NOT_ASSESSED. A candidate event is bound
  to `message=ex_hs2` + expected `tool` + planted `sessionId` + input
  field correspondence (ms/ms or s×1000, UTF-16 `n`) + the run's time
  window. An event present but field-mismatched is `FIELD_MISMATCH`,
  never folded into "not observed".
- `ELIGIBLE_FOR_COMPARISON` — YES/NO plus `INELIGIBILITY_REASONS`.
  Not-ready, cleanup incomplete, target or workbench-JS identity
  unpinned/mismatched, or missing phase epochs all disqualify a run from
  the formal matrix. A qualified run may still carry a real positive as a
  limited fact; a not-ready run with zero events is NOT a valid negative.

Runner guarantees: the manifest is written by the EXIT trap so every
terminal path (success, timeout, early exit, cancellation) leaves a
record. `total_runtime_s` (launch→end) and `observed_window_s`
(ready→end) are recorded separately. `--cursor-app` on a non-default path
refuses to run without an explicit `--expect-sha256`; the workbench
`workbench.desktop.main.js` artifact is pinned alongside the Mach-O.
Regression: `test-fixtures.py` (22 verifier/extractor fixtures),
`test-runner-stub.sh` (7 stub-target runs — never the real target).

## What this round can conclude at most

L2 correlation (Cursor process opened canary file / wrote queue key) and
L3-destination (which endpoints it connected to, when). It cannot conclude
field-level egress — that requires authorized MITM, deferred.
