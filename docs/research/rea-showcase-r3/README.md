# REA-SHOWCASE-R3-EVIDENCE-01

Research workspace for the round-3 evidence program. This directory contains
auditable baseline records, methodology notes, and per-task ledgers only.
**No application binaries, captured payloads, credentials, or raw network
captures are committed to this repository.**

## Scope (fixed for this round)

| Task | Position | Status |
|---|---|---|
| Cursor client data-flow audit | External flagship research; runtime minimal closed loop this round | **L2 closed-loop PASS** (3.24.12): file read → `ex_hs2` constructed → queued → bookmark persisted, default env, privacyMode=true. L3 content egress: UNKNOWN (authorized MITM pending). L1 span-level trace: in progress |
| `.pkg` inspection correctness | Independent correctness task in `rea-wt-pkg` worktree | **PASS**: defect confirmed + fixed (`120c2769a`, pushed); InstallerAlert: signed but arm64 tampered + notarization revoked |
| WebMCP `consequential` fidelity + 5-site pilot | Independent small task; method validation only | **PASS**: fix `449c58a37` pushed; 5-site pilot classified all target classes |
| `versus.pkg` container end-to-end | Requires original container; not substituted | BLOCKED / NOT_RUN |
| Cursor content-level network egress | Requires authorized MITM / system-trust change | NOT_RUN — awaits authorization |

## Evidence layer rules (binding)

- **L1 static artifact evidence**: code paths present in shipped bytes. Never
  presented as runtime behavior. Identical string-hit counts across versions
  do not imply identical behavior.
- **L2 local runtime observation**: reads, writes, queue entries, settings
  state observed in a specified environment. Never presented as network
  exfiltration.
- **L3 network observation**: bytes observed leaving the client. Destination-
  level observation (host/port/volume) is weaker than content-level
  (decrypted fields) and must be labeled as such. Never presented as
  server-side storage or training use.
- **L4 server-side/policy evidence**: vendor documents, ToS, subprocessors,
  forum statements. Never extended beyond its stated scope.
- Unknowns stay unknown. Intervention experiments are labeled separately
  from default-behavior observations.

## Reporting rules (binding)

- No claim of novelty, firstness, exclusivity, safety, or automatic
  detection unless independently demonstrated and cited.
- Every conclusion has a ledger entry: question, falsifiable claim,
  evidence location, evidence type, alternative explanation, unknowns,
  reproduction steps.
- Tool-call success or non-empty output is not a research conclusion.

## Layout

- `baseline/` — environment, git identity, artifact manifest, REA build
- `cursor/` — dataflow trace, runtime protocol, results, ledger
- `pkg/` — correctness findings, fixture matrix, oracle outputs
- `webmcp/` — method corrections, schema fidelity findings, pilot results
- `ledgers/` — cross-task conclusion ledger
