# REA-SHOWCASE-R3-EVIDENCE-01

Research workspace for the round-3 evidence program. This directory contains
auditable baseline records, methodology notes, and per-task ledgers only.
**No application binaries, captured payloads, credentials, or raw network
captures are committed to this repository.**

## Scope (fixed for this round)

Status is reported as RUN (did the procedure execute) / OBSERVATION (what
was actually observed, layer-tagged) / REVIEW (independent-checkable
state). "PASS" is not used to conflate the three.

| Task | RUN | OBSERVATION | REVIEW |
|---|---|---|---|
| Cursor L1 dataflow trace | DONE | full chain traced, semantically stable 3.14.7→3.24.12 (L1) | excerpts + offsets in `cursor/layer1-dataflow.md` |
| Cursor L2 runtime loop R3-CUR-RUN-1 | DONE (1 run, ~5 min) | read→`ex_hs2`→queue→bookmark observed under fresh-profile default state incl. stored privacyMode=true (L2); L3 egress UNKNOWN | sanitized excerpts + script + hashes committed `cursor/evidence/` |
| `.pkg` signature gate defect | DONE | pre-fix `signed:false` for every pkg; CONFIRMED vs crafted signed fixture | fix `120c2769a` + 78/78 tests + oracles committed |
| InstallerAlert signature | DONE (offline) | arm64 verify FAILURE observed (oracle); tamper attribution UNKNOWN; `spctl` host-policy revocation reported separately; REA `unknown`-status divergence OPEN | `pkg/correctness-report.md` §4 + oracle |
| WebMCP `consequential` fidelity | DONE | protocol carries it; REA dropped it | fix `449c58a37` + round-trip tests + real-site Evidence |
| WebMCP 5-site pilot | DONE | classes partially supported — see WEB-03 | `webmcp/pilot-results.md` (R3.1-corrected) |
| `versus.pkg` container | NOT_RUN — original container unobtained | — | BLOCKED pending authorized source |
| Cursor L3 content egress | NOT_RUN — needs authorized MITM | — | design doc pending |

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
