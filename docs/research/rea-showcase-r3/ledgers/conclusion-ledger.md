# Conclusion ledger

One entry per claim. A claim is only as strong as its evidence layer.
Statuses: `SUPPORTED` / `PARTIAL` / `REFUTED` / `UNKNOWN` / `NOT_RUN` /
`BLOCKED`.

## Template

```
### <ID> — <short title>
- Question:
- Falsifiable claim:
- Status:
- Evidence location:
- Evidence layer/type:
- Alternative explanation:
- Unknowns:
- Reproduction steps:
```

## Entries

### CUR-L1-01 — externalCliAnalytics dataflow exists in 3.23.23/3.24.9/3.24.12
- Question: does the shipped bundle contain code that reads external CLI
  history files and constructs `ex_hs2` events?
- Falsifiable claim: the marker set is present in all three preserved builds.
- Status: SUPPORTED (marker presence only — L1).
- Evidence location: `baseline/artifact-manifest.md` marker counts; per-version
  grep over `workbench.desktop.main.js`.
- Evidence layer: L1 static.
- Alternative explanation: markers could be dead code, server-gated, or
  behind settings; presence ≠ execution.
- Unknowns: trigger conditions, field contents, send path, per-version diffs.
- Reproduction: `grep -o '<marker>' <version>/.../workbench.desktop.main.js | wc -l`.

### CUR-L2-01 — externalCliAnalytics executes and reads both CLI histories (3.24.12, default)
- Question: does the code path actually run and read external history files
  in a default environment?
- Falsifiable claim: with only synthetic `~/.claude/history.jsonl` and
  `~/.codex/history.jsonl` present under an isolated `HOME`, a fresh
  unauthenticated 3.24.12 instance constructs `ex_hs2` events whose `ts` and
  `sessionId` byte-for-byte match the canary records, and persists
  `externalCliAnalytics.lastTimestamp.{claude,codex}` equal to the canary
  timestamps.
- Status: SUPPORTED (L2).
- Evidence location: `cursor/layer2-runtime-results.md`; extracted evidence
  under `/tmp/rea-r3/home-1791791263/evidence/` (not committed).
- Evidence layer: L2 local runtime.
- Alternative explanation: none identified for the propagation chain — the
  sentinel values existed nowhere else in the environment.
- Unknowns: L3 content egress; other versions/settings; `env_*` semantics;
  whether prompt content fields exist in events beyond `n` (length).
- Reproduction: see `cursor/runtime-protocol.md`; canary files in evidence dir.

### CUR-L2-02 — pipeline ran under privacyMode=true in this environment
- Question: does a privacy-mode setting state suppress the read/queue?
- Falsifiable claim: in this fresh-profile run, `privacyMode=true` /
  `PRIVACY_MODE_NO_STORAGE` coexisted with observed reads + `ex_hs2` queue
  entries.
- Status: SUPPORTED for this environment (L2); NOT generalizable — fresh
  profile default may differ from logged-in/upgraded profiles.
- Evidence location: `state-vscdb-scoped.txt`; `layer2-runtime-results.md` §5.
- Evidence layer: L2.
- Alternative explanation: key written after the fact, or privacy-mode check
  not consulted by this component — either way the read+queue occurred while
  the stored state was true at query time.
- Unknowns: ordering (was privacyMode true *at read time*?); logged-in
  profile behavior; server-side enforcement.
- Reproduction: launch fresh profile per protocol; scoped sqlite query.

### CUR-L3-01 — network egress of ex_hs2
- Status: UNKNOWN. Destination-level connections observed (~24 TLS
  connections through VPN fake-IP); content-level not captured (MITM
  requires authorization not granted this round). Sentry queue file was
  empty at snapshot — ambiguous.
- Reproduction: authorized MITM or vendor-documented endpoint inspection,
  pending authorization.
