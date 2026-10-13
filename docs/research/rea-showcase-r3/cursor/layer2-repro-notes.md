# L2 reproducibility notes (R3.2/R3.3)

RUN-1's positive did not reproduce in subsequent host attempts. The
record below distinguishes observed facts from candidate explanations;
none of the silent attempts currently qualify as a clean negative.

## Attempt inventory (corrected R3.3)

| Run | Window | Outcome | Sample status |
|---|---|---|---|
| smoketest1 | 60 s | zero externalCliAnalytics activity | exploratory; window too short |
| smoketest2 | 200 s | zero activity | observation; readiness not yet verified by tooling |
| smoketest3 | 240 s | target ran, but the **runner script was edited mid-run** and died before writing the manifest | **PROGRAM ABORT — invalid sample, excluded** |
| smoketest5 | 240 s | runner died on `pgrep`/`pipefail` bug after termination | program defect in cleanup; target-side state unmeasured |
| smoketest6 | 240 s | zero activity; launch probe 200; env -i; manifest written by pre-readiness runner | observation; readiness NOT measured by tooling |

**smoketest3 is not counted as a replicate.** At most two silent
observations (smoketest2, smoketest6) exist, and neither was produced
under a runner that verified workbench readiness at the time — the
readiness check only exists in the R3.3 runner.

## smoketest6 — observed facts only

- `network_probe_at_launch`: `curl https://api2.cursor.sh/` returned 200
  at launch. This evidences that ONE root-path request succeeded; it does
  NOT evidence that Cursor's own configuration requests succeeded, nor
  WAN health inside the observation window.
- No `ex_hs2` breadcrumbs; no `externalCliAnalytics.*` keys; no
  `cursor-sentry-events.log` written. The `sentry/` dir holds
  `scope_v3.json` + `session.json` but no queue file.
- `state.vscdb` contains **7 keys**. RUN-1's frozen state.vscdb contains
  **101 keys** including `cursor.*` remote-gate values.

## What the 101-vs-7 key difference does and does not show

It is a **profile-state difference**. It does NOT independently prove
that a remote configuration request was never made, that it failed, that
the externalCliAnalytics poll never ran, or that a remote kill switch is
active. An alternative not yet excluded: **workbench initialization did
not complete**, which would simultaneously explain absent `cursor.*`
keys AND the inactive contribution. The RUN-1 comparison is against the
database frozen at that time, not any live post-run state.

## Candidate explanations (all HYPOTHESES, none eliminated)

1. Workbench/initialization did not reach the contribution-activation
   condition in the silent runs (cause unspecified — remote gate
   resolution, lifecycle timing, or another dependency).
2. Intermittent WAN degradation during the smoketest window (a 23.7 GB
   image pull was dropping connections; probes prove only instant
   reachability of one endpoint).
3. Server-side gate state differed between 07:48Z and 17:45Z+.
4. Some first-run condition in RUN-1 not reproduced — no specific
   candidate evidenced.

## Procedural defects found and fixed (R3.2/R3.3)

- **Ambient environment leaked to the target.** RUN-1 and smoketest2/3
  launched with `env HOME=…`, passing the parent's full environ —
  including API tokens — into the target's process environ. The values
  were visible to the target process. Whether Cursor read or transmitted
  them is NOT observed; the exposure itself is the defect. Scope record
  (variable names + dispositions, no values) is held in controlled local
  storage, not committed. Runner now uses `env -i`.
- **"fake HOME" is a path redirect, not filesystem/permission
  isolation.** Earlier wording overstated the boundary. Switching to
  `env -i` also changed other environ inputs, so RUN-1 and smoketest6
  differ in MORE than a hygiene dimension — they are not a controlled
  one-variable comparison.
- **Termination incompleteness.** `pgrep -P` misses Electron helpers
  (observed surviving). Runner now terminates by unique `user-data-dir=`
  match and reports remaining-process count; `user-data-dir` matching
  still only covers processes that carry the arg — remaining count is
  reported, not silently trusted.
- **Runner defects:** bash 3.2 empty-array expansion, `pipefail`+`pgrep`
  silent exit, mid-run script edit (smoketest3), `ioreg` missing from
  `env -i` PATH (smoketest4). Runs now pin script sha256 + computed
  target sha256 in the manifest.
- **Verifier defects (R3.3, reproduced by external review):** codex
  event-ts compared to input seconds instead of ms (rejected correct,
  accepted wrong); missing `hashes.txt` silently skipped integrity;
  raw/dedup subset check compared only counts; bookmark check used
  substring match; `n` used Python len rather than UTF-16 units; missing
  inputs degraded instead of failing. All fixed; regression fixtures
  F1–F11 in `tools/test-fixtures.py`, 11/11 matched.
- **Verifier semantics split:** EVIDENCE_INTEGRITY / RUN_VALIDITY /
  OBSERVATION are now independent verdicts; a valid run with no events
  reports `NOT_OBSERVED_WITHIN_WINDOW`, not a generic FAIL.
