# L2 reproducibility notes (R3.2)

Honest negative — the RUN-1 positive did NOT reproduce in a first R3.2
host smoke run. This is recorded as an observation, not a refutation.

## smoketest2 — canary run, 200 s window (run dir `smoketest2-1791827144-51158`)

- Same Cursor 3.24.12, same launch args as RUN-1 (`--user-data-dir`,
  `--disable-crash-reporter`), fresh fake HOME, fresh canary inputs
  (input hashes `c9170201231f…` claude / `15ddb6a48787…` codex).
- Result: **no `ex_hs2` breadcrumbs, no `externalCliAnalytics.*` keys in
  state.vscdb, no `cursor-sentry-events.log` written at all** — the
  telemetry event writer never produced event records, so the
  contribution apparently never polled within 200 s.
- `sentry/` directory exists with `scope_v3.json` + `session.json` but no
  queue file → telemetry identity initialized, no events generated.
- verify-evidence verdict: FAIL on canary checks (correct — events absent);
  all hash checks pass; tools behave as designed on a negative run.

## smoketest6 — canary run, 240 s, WAN confirmed up, env -i

- `network_probe_at_launch`: api2.cursor.sh HTTP 200 at launch.
- Still zero externalCliAnalytics activity: no events, no bookmarks, no
  sentry event log, `state.vscdb` holds **7 keys** only.
- RUN-1's live state.vscdb held **101 keys**, including `cursor.*`
  remote-gate values (`cursor.startupConnectTransport.gate`,
  `cursor.modelCatalogOwnKey.gateEnabled`, `glass.sharedApplicationStorage
  .gateEnabled`, …). The three silent runs hold ZERO `cursor.*` keys —
  the remote configuration fetch never landed in any of them.
- Strong correlation (not proof): RUN-1 = remote config populated + poll
  fired; silent runs = remote config absent + poll silent. Consistent
  with remote gate resolution being required before
  externalCliAnalytics proceeds — i.e. the client registry's
  `default:!0` alone may NOT make the path effective. The remote
  kill-switch reading from the L1 audit is corroborated, unproven.
- Alternative explanations not excluded: intermittent WAN degradation
  during the smoketest window (concurrent 23.7 GB image pull was
  dropping connections); different first-run conditions; a server-side
  gate change between 07:48Z and 17:45Z+.

## Differences vs RUN-1 (candidate explanations, all HYPOTHESES)

1. **WAN stall during the run.** Concurrent `tart` image pull was dropping
   connections repeatedly at that time. If the `enable_ex_hs` feature-gate
   resolution (or another remote dependency the Eventually contribution
   awaits) blocks on network, a stalled WAN could delay the first poll
   beyond 200 s. Consistent with L1 finding that the client-declared
   `default:!0` may be subject to remote override semantics — i.e.
   "effective switch" may need a remote fetch before the contribution
   proceeds. UNVERIFIED.
2. **Run-to-run variance in Eventually timing** — possible but less
   consistent with zero event-log activity.
3. **Some first-launch condition in RUN-1 not present here** — no evidence
   for a specific candidate.

## Why this matters

- Confirms the R3.1 correction that "default:true in the client registry"
  ≠ "effective switch" — run-time conditions (possibly remote gate
  resolution) influence whether the code path executes.
- Reproducibility is exactly what the R2 run in the L3 matrix is for;
  the L3 runs should record WAN state so this variable is measured, not
  guessed.

## Toolchain note

- 60 s and 200 s windows both produced zero externalCliAnalytics activity
  on this host. Future runs should use ≥240 s windows and record network
  reachability (api2.cursor.sh) at launch time in the manifest.

## Procedural defects found and fixed (R3.2, applies retroactively to RUN-1)

- **Ambient environment leaked to the target.** RUN-1 and smoketest2/3
  launched with `env HOME=…` which overrides only HOME — the parent's full
  environment (including API tokens present in the parent shell) reached
  the target's process environ. This did not affect the canary findings
  (the fake HOME isolated filesystem state) but is a hygiene defect:
  fixed via `env -i` minimal environment in `run-experiment.sh`. No
  credential reached any committed artifact.
- **Termination incompleteness.** `pgrep -P` only follows direct
  children; Electron helpers (gpu/network/renderer/crashpad) do not stay
  under the launch pid and survived scripted kill (observed live after
  run end; manually killed). Fixed: terminate by unique
  `user-data-dir=` path match and report remaining count in the manifest.
- **verify-extract bugs fixed:** `hashes.txt` hashed itself (now
  excluded); `.claude/history.jsonl` and `.codex/history.jsonl` basename
  collision (now full paths recorded).
- **Edit-while-running hazard:** smoketest3's manifest write died on an
  unbound variable when the script was edited mid-sleep — bash re-reads
  the file by byte offset. Runs are now only launched from the committed
  script version.
