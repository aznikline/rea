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

### CUR-L1-01 — externalCliAnalytics markers present in 3.14.7→3.24.12
- Question: does the shipped bundle contain code that reads external CLI
  history files and constructs `ex_hs2` events?
- Falsifiable claim: the marker set is present in all five preserved builds.
- Status: SUPPORTED (marker presence only — L1). Earliest OBSERVED = 3.14.7;
  first-introduction version UNKNOWN.
- Evidence location: `baseline/artifact-manifest.md` marker counts; per-version
  grep over `workbench.desktop.main.js`.
- Evidence layer: L1 static.
- Alternative explanation: markers could be dead code, server-gated, or
  behind settings; presence ≠ execution (see CUR-L2-01 for execution in
  3.24.12 only).
- Unknowns: per-version code diffs inside traced spans (in progress).
- Reproduction: `grep -o '<marker>' <version>/.../workbench.desktop.main.js | wc -l`.

### CUR-L1-02 — dataflow fully traced; client-side default true; extra fields found
- Claim: `workbench.contrib.externalCliAnalytics` (lifecycle Eventually)
  runs `_poll()` at construction + hourly cron; gated by
  `experimentService.checkFeatureGate("enable_ex_hs")` whose registry literal
  is `{client:!0,default:!0}` — the client-declared default is true, while
  the effective gate remains subject to remote-override semantics not yet
  resolved; reads `~/.claude/history.jsonl`,
  `~/.codex/history.jsonl`, AND `~/.claude/projects/<dashed-proj>/sessions-index.json`;
  emits `ex_hs2{tool:"ac"|"cx", ts, sessionId verbatim, n=text-length,
  msgCount(claude)}`; bookmarks via `externalCliAnalytics.lastTimestamp.*`.
  Semantically stable across 3.14.7→3.24.12.
- Status: SUPPORTED (L1, offsets + excerpts in `cursor/layer1-dataflow.md`).
- Also: `workbench.contrib.pathInspection` emits `env_{cx,ac,az,gl,agent}` /
  `env_ag` when competitor executables/apps are detected — distinct feature.
- Unknowns: remote flag override; analyticsService internal gates; wire
  egress (L3); privacyMode consult absent *in this path* — pipeline-level
  gating unverified.

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

### PKG-01 — inspect_signature misclassified every .pkg (defect, fixed)
- Claim: `rea inspect-signature <x.pkg>` reported `signed:false` /
  "Artifact is not signed." for every pkg because the codesign-based path
  had no format gate and cannot evaluate XAR-level signatures.
- Status: SUPPORTED → defect CONFIRMED; fixed at the boundary.
- Evidence: `pkg/correctness-report.md` §1–3; crafted `crafted-signed.pkg`
  (real `<signature>` TOC element, oracle `pkgutil --check-signature` =
  "invalid signature") produced identical `signed:false` to an unsigned pkg.
- Fix: `integration/feat/pkg-inventory` commit `120c2769a` (pushed to fork) —
  `inspect_signature` now refuses non-Mach-O targets with
  `AnalysisCapabilityUnavailableError`; 78/78 boundary tests + check:fast.
- Remaining gap (not fixed): inventory drops `<signature>` silently
  (feature-sized); pbzx/member limitations don't aggregate to top-level
  coverage; Distribution/PackageInfo unsemantic-parsed without limitation.

### PKG-02 — InstallerAlert: arm64 verification FAILURE observed; attribution unknown (R3.1 corrected)
- Claim (bounded): for the extracted `Mac-Installer.InstallerAlert` in this
  verification environment, `codesign --verify --deep --strict` exits 1 with
  `invalid Info.plist (plist or signature have been modified)`, `In
  architecture: arm64`.
- Status: SUPPORTED (oracle output observed; **attribution to post-signing
  tamper is RETRACTED** — the diagnostic does not establish which bytes were
  modified, by whom, or when; bundle-context loss during sample extraction
  is a live alternative).
- Evidence: `pkg/correctness-report.md` §4; `pkg/oracle/InstallerAlert-oracle.txt`.
- Separate observations (not merged into one claim):
  (a) `spctl` host-policy evaluation reports revocation — host system-policy
  result, NOT REA offline parsing, and not proof of revocation time/reason;
  (b) OPEN: `rea-wt-sig` maps this definitive codesign rejection to
  `verification.status:"unknown"` — `"invalid Info.plist"` absent from
  `INVALID_SIGNATURE_REASONS` (`CodesignVerification.ts:52-66`). Reported,
  not fixed.
- Caveat: applies to this extracted binary only; nothing inferred about the
  versus.pkg container, which remains NOT_RUN.

### WEB-01 — `consequential` annotation dropped by normalization (fixed)
- Claim: CDP `WebMCP.Annotation` carries optional `consequential`; REA's
  `normalizeTool` dropped it.
- Status: SUPPORTED → fixed, `fix/webmcp-annotations` commit `449c58a37`
  (pushed to fork). true/false/absent(null)/older-capture distinctions
  preserved; Evidence bundle + CLI re-read round-trip verified, including a
  real zapier.com declaration (`consequential:false`) via `ev_e451abd5…`.
- Note: `debugging` annotation exists on Chromium main (JS-side Chrome ≥156)
  and is NOT surfaced — recorded gap.

### WEB-02 — prior "dual-channel nobody does" claim retracted
- Status: REFUTED. Mudpie.ai/Lazyweb ran 6,934 sites × two modes with
  enrollment classes; see `webmcp/method-notes.md`. REA's surviving
  differentiators: strictly passive (no invoke/evaluate/navigate), per-frame
  identity, hash-bound Evidence provenance, machine-readable unavailable
  classes.

### WEB-03 — 5-site pilot ran; classifications partially supported (R3.1 corrected)
- Claim: `rea discover-webmcp-tools` (Chrome 154, dedicated profile,
  ~60 s/site, default vs `WebMCPTesting` flag) classifies sites correctly.
- Status: PARTIAL — method exercised; semantic classes not all proven.
  zapier.com deployed-token (5 tools): SUPPORTED. example.com negative:
  SUPPORTED (single frame, no token, no markers). feverup.com polyfill:
  SUPPORTED (CDP-invisible both modes + static markers). gillette.de
  code-present: SUPPORTED for "0 default / 4 flag + isThirdParty token";
  the causal story (third-party-scoped token fails to enroll the document)
  is a HYPOTHESIS — inferred, no Chrome-internal diagnostic. cnn.com: no
  tools in observed frames; the 7 `unsupported_url` subframes are
  **unobserved, not negative**.
- Evidence: `webmcp/pilot-results.md`.
- Unknowns: interaction-gated registrations; polyfill confirmation needs
  static/script channel; mid-load redirect (`target_not_allowed`) handling.

## R3.2 updates

### CUR-05 — L2 evidence now independently checkable; experiment program split
- Status: SUPPORTED — Lead recomputed `evidence/hashes.txt` 5/5, canary
  lengths (44/42) match `n`, sessionIds/timestamps cross-check, corrected
  24.1 s delta confirmed.
- Counting fix: raw breadcrumb excerpt has each record twice (log writes
  duplicate breadcrumbs); only 2 deduplicated events counted. R3.2 tools
  emit raw + deduped views separately.
- `evidence/extract.sh` marked DEPRECATED (rewrites inputs, fixed paths,
  launches target, no wait/cleanup). Replaced by `tools/run-experiment.sh`
  (unique run dir, explicit intervention manifest), `tools/
  extract-evidence.sh` (read-only, refuses overwrite), `tools/
  verify-evidence.sh` (hash/field/timing/dup checks, no launch).

### CUR-06 — L3 egress: EXECUTION AUTHORIZED (VM path only)
- R3.2 authorization: one-shot revertible macOS VM; Cursor, mitmproxy,
  temporary CA all inside guest; synthetic data only; no host trust/proxy/
  pf/VPN changes; no host-user fallback. Fixed matrix R0 (none) / R1
  (canary) / R2 (repeat). proxy-delivered / upstream-sent /
  response-observed reported separately.
- Status: IN PROGRESS — tart 2.40.1 installed (checksum-verified);
  `macos-sequoia-vanilla` pull in progress; see `cursor/l3-egress-design.md`.

### PKG-03 — `invalid Info.plist` mapping fixed on signature-posture
- Status: SUPPORTED → fixed on `integration/feat/signature-posture`
  commit `cede1a6f1` (pushed to fork). Per review: NOT a third upstream PR —
  module does not exist on current main; attached to parent feature.
- Benign oracle: ad-hoc signed app verifies valid; Info.plist tamper
  reproduces exact codesign rejection; classifier now maps to `invalid`.
  Negatives covered: operational failures and nested filenames containing
  the diagnostic phrase stay non-invalid.
- No attribution: `invalid` = verification result only, not who/when/why.
- Note: unrelated pre-existing host failure — `machoSliceReader.test.ts`
  lipo cpusubtype disagreement on macOS 27 /bin/ls (environmental).

### OPS-01 — PR CI status
- #2262 (head `64af56e82`, stale-comment fix pushed) and #2263 (head
  `354ec7cee`): CI runs 38285835728 / 38283242870 / 38283351994 completed
  with `action_required` and empty job lists = first-time-contributor
  maintainer approval needed. Not a code failure; no further pushes made
  to chase CI. Local tests remain separately reported.
- Upstream main advanced to `ad08510a1` — recorded as new BASE reference;
  R3.1 test identities preserved per old base.

## R3.2b updates

### CUR-07 — L2 positive did NOT reproduce in three host re-runs (R3.2)
- smoketest2 (200 s), smoketest3 (240 s, died mid-manifest — script
  defect, fixed), smoketest6 (240 s, env -i, WAN 200 at launch):
  **zero externalCliAnalytics activity** — no breadcrumbs, no bookmarks,
  no sentry event log.
- Correlating observation: RUN-1 state.vscdb = 101 keys incl. remote
  `cursor.*` gates; all silent runs = 7 keys, zero `cursor.*`. Remote
  config never landed → poll silent. Consistent with effective gate
  needing remote resolution (client `default:!0` alone insufficient).
  NOT proof; alternatives recorded in `cursor/layer2-repro-notes.md`.
- Evidence (sanitized): `cursor/runs/smoketest2/`, `cursor/runs/smoketest6/`.
- Tools hardened: `env -i` isolation (RUN-1's ambient env leak recorded),
  process-group-safe termination, manifest records WAN probe + remaining
  procs; verify-extract bugs fixed. See `cursor/tools/`.
- RUN-1's positive stands as observed for that run only.

### OPS-02 — L3 VM image pull in progress
- tart 2.40.1 verified + installed user-local; sequoia-vanilla 23.7 GB
  pull in progress through intermittent WAN (auto-retry). Guest mitmproxy
  12.2.3 arm64 staged + hashed. Host trust/proxy baseline snapshotted for
  post-experiment unchanged-check.

## R3.2b updates

### CUR-07 — L2 positive did NOT reproduce in three host re-runs (R3.2)
- smoketest2 (200 s), smoketest3 (240 s, died mid-manifest — script
  defect, fixed), smoketest6 (240 s, env -i, WAN 200 at launch):
  **zero externalCliAnalytics activity** — no breadcrumbs, no bookmarks,
  no sentry event log.
- Correlating observation: RUN-1 state.vscdb = 101 keys incl. remote
  `cursor.*` gates; all silent runs = 7 keys, zero `cursor.*`. Remote
  config never landed → poll silent. Consistent with effective gate
  needing remote resolution (client `default:!0` alone insufficient).
  NOT proof; alternatives recorded in `cursor/layer2-repro-notes.md`.
- Evidence (sanitized): `cursor/runs/smoketest2/`, `cursor/runs/smoketest6/`.
- Tools hardened: `env -i` isolation (RUN-1 ambient env leak recorded),
  process-group-safe termination, manifest records WAN probe + remaining
  procs; verify-extract bugs fixed. See `cursor/tools/`.
- RUN-1's positive stands as observed for that run only.

### OPS-02 — L3 VM image pull in progress
- tart 2.40.1 verified + installed user-local; sequoia-vanilla 23.7 GB
  pull in progress through intermittent WAN (auto-retry). Guest mitmproxy
  12.2.3 arm64 staged + hashed. Host trust/proxy baseline snapshotted for
  post-experiment unchanged-check.

## R3.3 updates

### CUR-08 — verifier defects fixed; three-tier verdicts (R3.3)
- External review reproduced 4 verifier misjudgments (ms/s unit, skipped
  missing hashes.txt, count-only dedup, substring bookmarks). All fixed:
  exact key+value bookmarks, UTF-16 code-unit `n`, ms-scaled codex ts,
  real set relations, packaged inputs required not degraded.
- EVIDENCE_INTEGRITY / RUN_VALIDITY / OBSERVATION are now independent;
  a complete valid run with no events = NOT_OBSERVED_WITHIN_WINDOW.
- Regression: tools/test-fixtures.py F1-F11, **11/11 matched**,
  including the 4 review counterexamples + field-order/whitespace,
  corrupt breadcrumb, non-BMP char, early-exit, not-ready, missing-input.
- Re-extracted committed packages (runs/smoketest2, runs/smoketest6) now
  carry inputs/, extract-report.json, package-relative hashes. smoketest6
  verdict: INTEGRITY PASS / VALIDITY QUALIFIED (pre-readiness manifest) /
  NOT_OBSERVED_WITHIN_WINDOW.

### CUR-09 — run validity re-scoped
- smoketest3 = PROGRAM ABORT (script edited mid-run) — excluded from
  replicate count. smoketest5 = cleanup-stage runner defect.
- Valid silent observations: smoketest2 + smoketest6 only; neither had
  readiness measured at run time (check added in R3.3 runner).
- 101-vs-7 keys = profile-state difference only; "remote config never
  arrived" / "poll never ran" / "remote kill switch" NOT proven; workbench
  under-initialization is a live alternative explanation.
- api2 root-path 200 = one probe at one instant, not Cursor-request or
  window-level WAN evidence.

### SEC-01 — ambient env exposure scope (controlled storage)
- RUN-1/smoketest2/3 passed parent environ into the target process.
  Variable-name scope recorded locally (NOT committed, no values):
  ARK_API_KEY, GEMINI_API_KEY, GOOGLE_GENERATIVE_AI_API_KEY,
  KIMI_API_KEY, VERCEL_TOKEN. Visibility ≠ read/egress — neither
  observed. Rotation is the user's decision.

### OPS-03 — same-env base/head for machoSliceReader failure
- tests/boundary/providers/native/machoSliceReader.test.ts FAILS
  identically at base 4c0e0658 and head cede1a6f1 on this host
  (lipo cpusubtype disagreement on macOS 27 /bin/ls) — pre-existing,
  not introduced by cede1a6f1. Still a portability gap on the branch.

### OPS-04 — R3.3 housekeeping
- #2262/#2263: zero review comments, zero review state changes; CI
  runs remain action_required (empty jobs). Status recorded as
  maintainer-approval-blocked; no CI-chasing commits.
- tart pull attempt 1 died on repeated network loss after partial layer
  cache; bounded retry loop (5 attempts, 60 s backoff) running in
  background. Image digest will be pinned on first successful resolve.
- upstream main readings (all timestamped, moving target — no chasing):
  `974f11d01` (R3 baseline), `d96550f2f` (R3.1 PR base), `ad08510a1`
  (R3.1 review-time), `4773c152b` (R3.3 reviewer read), `ca2d15b3e`
  (R3.3 agent re-fetch, current).

### OPS-05 — R3.4 pipeline interface fixes (2026-10-13)
- Lead's focused review (REA_R34_focused_review.zip, NOT accessible in
  this environment — fixes implemented independently per its precise
  defect descriptions; do not record as "Lead patch merged"):
  * R0 `history=none` zero-byte JSONL inputs = "no records" semantics,
    not corrupt — verifier now honors mode (empty OK in none, FAIL in
    canary).
  * `covered.add(rel)` no longer conflates "required to exist" with
    "hash-covered" — unlisted inputs fail integrity.
  * `cancelled` runs are terminal-recorded but never eligible.
  * Missing launch/obs_end → window unverifiable = soft mismatch →
    OBSERVED_PARTIAL + ineligible (no more TypeError crash).
  * ready_epoch_s required when readiness is claimed — missing →
    ineligible.
- Pipeline regression T8–T10: real runner→extract→verify chain covers
  R0 empty-history negative, R1 positive, R2 repeat, cancelled.
  Suite: 27/27 fixtures + 10/10 stub runs.
- PR #2465 (split/intrinsic-boundaries @ 8d5e11efc): Open/Draft,
  opened 2026-10-13T11:28:32+08:00, no checks reported (same
  maintainer-approval block as #2262/#2263). Prior "network-blocked"
  state is historical only.
- check:pr framing corrected: "candidate-relevant gates pass; full
  suite has base-reproduced failures", not "all gates pass".

### OPS-06 — VM image resolved; precheck OK
- tart pull COMPLETED; no active pull process remains. The earlier
  "still retrying" status was stale — progress-by-cache-size was the
  wrong metric (cache 28G + vms 28G = the resolved image plus the VM
  clone, not download progress).
- Pinned digest: ghcr.io/cirruslabs/macos-sequoia-vanilla
  @sha256:57a83b1b52f928f5b11b0963927178fd6c4cac52c315279f227c27cc5ab81587
- rea-l3-vm exists (30G sparse on-disk), boots headless, SSH admin@
  192.168.64.2 alive, macOS 15.7.7 arm64 — environment precheck PASS.
  Cleanly shut down after precheck to free host resources.
- Host disk 92% used (36Gi free) — flag before guest installs.

### R3.5 — first guest L3 observation (constrained)
- c47938400 pushed to fork/research/showcase-r3; R0b/R1/R2 all
  PASS/VALID/NOT_OBSERVED per packaged-observation scope.
- Corrections appended in l3-guest-run1/RESULTS.md: R0 window is
  6010.8 s wall-clock inflated by VM suspend/resume (excluded from
  equal-window comparison); capture-r0.mitm is mixed-provenance; the
  sentry-mirror log is a privacy-mode-only artifact.

### R3.6 — no-login activation matrix complete (all negative in scope)
- U0 run-1791882586-876: PASS/VALID/NOT_OBSERVED/ELIGIBLE.
- U1 run-1791884333-1354 / U2 run-1791884745-1853 / U2g
  run-1791885583-2605: PASS/QUALIFIED/NOT_OBSERVED/NO
  (workbench_readiness_not_reached — folder-window logdir naming
  artifact of the detector; renderer.log shows loaded workbench).
- U2g additionally verified the target window on-screen in the admin
  GUI session; Cmd+I injected; panel state unverified (Screen
  Recording TCC absent — screenshots return wallpaper only).
- Network: api2.cursor.sh /extensions-control only (u0–u2), zero
  Cursor flows in u2g; zero canary/ex_hs2/api3 markers in container
  bytes; lsof shows no direct egress, no UDP; NetLog (truncated)
  corroborates api2-only.
- Static: enable_ex_hs default=true; ex_hs2 egress targets
  api3.cursor.sh/tev1/v1 (statsig proxy); sentry-mirror is
  privacy-mode-only; ≥4 non-auth explanations remain for
  non-observation. "Login required" NOT demonstrated.
- No-login scope closed: NOT OBSERVED WITHIN THIS SCOPE.
