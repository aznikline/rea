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

(Further entries are appended by task agents under `cursor/`, `pkg/`,
`webmcp/` and consolidated here.)
