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
