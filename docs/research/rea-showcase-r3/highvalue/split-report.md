# integration/high-value split report

Date: 2026-10-13
Upstream base: `origin/main` = `ca2d15b3ee965bd7ab27204cdf4b96b117d148c1`
(re-fetched during this session; it has advanced past the previously observed
`ad08510a113d7a9b8d92fb1e385757880e469869` and the reviewer-seen
`4773c152bc5f299fa682575bb8d1efea7587c7bc`).

Source topics on `integration/high-value` (`1502a9b01`):

- intrinsic-boundaries: merged from `origin/codex/fix-intrinsic-invocation-boundaries`
  (`a6de554e2` merge of main + `1a322ab75`; the only topic commit is `1a322ab75`).
- compatibility-first: merged from `feat/compatibility-first-analysis-20261012`
  (topic commits `16338af50`, `dc8a19cec`, `f11061818`, `dd2a2598b`; the
  origin branch has since been deleted).

## Candidate 1: split/intrinsic-boundaries

- Branch: `split/intrinsic-boundaries` on fork (`ssh://git@ssh.github.com:443/aznikline/rea.git`)
- HEAD: `85ad41e55de2aee43fbc775f1492672185f5cd65`
- Commits: 1 — `fix(javascript): preserve intrinsic invocation read identity`
  (cherry-pick of `1a322ab75`, conflicts resolved against current main).

### File scope (7 files, +238/−87)

- `src/domain/javascript/javascriptIntrinsicInvocation.ts`
- `src/domain/javascript/javascriptElectronMemberWrites.ts`
- `src/domain/javascript/javascriptModuleInterop.ts`
- `src/domain/javascript/electronIntrinsicCapture.test.ts` (new)
- `src/domain/javascript/electronModuleInterop.test.ts`
- `tests/acceptance/applications/electronModuleInteropCli.test.ts`
- `docs/javascript-artifact-reconstruction.md`

### What it prevents / delivers

Intrinsic write tracking moved from the `SemanticPropertyPathCoverage` class to
exact recorded paths matched by `intrinsicWriteCovers`; invocation member reads
(`.call`/`.apply`/`.bind`) are checked separately from the earlier function
capture; comma-expression callees resolve to their final value; call effects are
retained at AST `exit` so callee-prefix effects are classified after nested
effects are collected.

Concrete counter-example (new regression tests): with the Rolldown
`__toESM` interop inlined,

```js
const define = Object.defineProperty;
const metadata = {};
(Object.defineProperty = replacement, Object.defineProperty)(metadata,"x",{value:1});
```

poisons the intrinsic and yields zero `browser_windows` (the write is retained
before the invocation is classified), while

```js
const define = Object.defineProperty;
const metadata = {};
Object.defineProperty(metadata,"x",(Object.defineProperty = replacement,{value:1}));
```

retains the captured callee and still yields one window. Likewise
`(0,Object.defineProperty)(Object,"create",{value:customCreate})` and
`const change = Object.defineProperty.call; change(null,Object,"create",{value:...})`
are conservatively rejected instead of silently admitted.

### Rebase divergence resolved

Upstream `9d8e42bdd` (#1912) replaced the old path-stripping of trailing
`.call`/`.apply` with explicit receiver tracking
(`explicitReceiver`, `expandJavaScriptInvocationArguments`). Under that
machinery an identifier bound to an intrinsic `X.call` read
(`const change = Object.defineProperty.call; change(...)`) derived no callable
and returned `undefined` — i.e., the call retained no effect at all, so three
of the ported "rejects intrinsic writes through a bound mutator" cases failed
initially. Resolution: when the callee resolves to an invocation member read
but names no callable, the resolver now returns `{ kind: "opaque" }`
(`javascriptIntrinsicInvocation.ts` ~line 140) — unknown effect rather than
proof of no write — matching the topic's conservative contract. Upstream's
plural-identity `origin()` API and `options.intrinsicPath` injection were
preserved; the `exit`-phase call-effect retention was re-expressed on that API.

### Test evidence (same environment, macOS worktree, Node per .nvmrc)

- `npm run check:fast`: PASS (typecheck + lint, both tasks).
- `npm run test:focused -- src/domain/javascript/electronIntrinsicCapture.test.ts
  src/domain/javascript/electronModuleInterop.test.ts
  tests/acceptance/applications/electronModuleInteropCli.test.ts`:
  **207/207 pass** (3 files).
- `npm run test:local` on 7 neighboring domain test files (wrapped call paths,
  semantic calls/member_mutations/ambient writes/recovered arguments):
  **458/458 pass**.
- Base `origin/main` (same env, `rea-wt-split-cf`): same focused set minus the
  new test file: **191/191 pass**; no pre-existing failures observed.

## Candidate 2: split/compatibility-first

- Branch: `split/compatibility-first` on fork.
- HEAD: `ca2d15b3ee965bd7ab27204cdf4b96b117d148c1` — **identical to the base;
  zero remaining delta. No PR should be opened for this topic.**

### Why the diff is empty

Every deliverable of the four topic commits already exists in current
`origin/main`, almost entirely via squash-merged PR #2122
(`58fb37207 feat(analysis): add opt-in retained inventory and WASM views`),
plus follow-ups:

- `16338af50` (measure harness): upstream `experiments/analysis-efficiency/`
  already contains strictly larger `measure.mjs` (854 vs 471 lines),
  `corpus.json` (240 vs 90, including the same `obsidian.asar` entry),
  `resource-run.py` (214 vs 127) and a 580-line README.
- `dc8a19cec` (typed retained inventory views): upstream already exports
  `artifactNodeSchema`, `artifactOccurrenceSchema`, `artifactEdgeSchema`,
  `artifactGraphManifestSchema` (`artifactGraph.ts`), defines
  `artifactInspectionOutputSchema` (`artifactInspection.ts:112`), and wires
  `inventoryViewSchema`/`inventorySummarySchema`/`projectArtifactInventoryView`
  for both `inspect_artifact` and `inventory_artifact` parents
  (`analysisView.ts:140,249,557-558`). The ported test string
  `"keeps complete ZIP output and reads retained inventory views after the
  source is removed"` exists verbatim at
  `tests/boundary/mcp/artifactMcp.inlineInventory.test.ts:391`. Upstream's
  `artifactInventoryView.ts` is a superset (adds
  `validateArtifactInventorySubject` provenance checks).
- `f11061818` (opt-in retained summary delivery): upstream already has
  `artifactInspectionInputSchema.detail` with the identical description text
  (`artifactToolContracts.ts:19-25`), `artifactInventorySummaryViewResultSchema`
  in `artifactOutputSchemas.inspect_artifact` (`toolOutputSchemaGroups.ts:396`),
  the `parametersForExecution`/`projectEvidence` hooks
  (`registerEvidenceTools.ts:32-36,70,118`), `evidenceById` plumbing
  (`registerArtifactTools.ts`, `createServer.ts`), the `detail === "summary"`
  dispatch (`registerArtifactTools.ts:41`), and `compare.mjs` (157 lines vs
  the topic's 99).
- `dd2a2598b` (Obsidian paired-run checkpoint): upstream README already has
  `## Obsidian delivery checkpoint` (line 233); `results/` is intentionally
  gitignored upstream, matching the commit's own "detailed generated experiment
  JSON stays outside the final tree" convention.

### Test evidence

Branch == base, so candidate behavior is base behavior by construction.
Same-env base run (this worktree): `test:focused` on the two shared JS test
files passed 191/191; `check:fast` passed in the sibling worktree on the same
base. No additional runs needed for an empty diff.

## Dependencies between the candidates

None. The topics touch disjoint areas (`src/domain/javascript` intrinsic
invocation vs `src/domain/analysisView`/artifact contracts + experiment
tooling). `split/intrinsic-boundaries` is self-contained on current main;
`split/compatibility-first` requires nothing because it ports nothing.

## Remaining gates / caveats

- `split/intrinsic-boundaries`: fast checks and focused/source tests pass;
  `check:pr` (full local gate) and real-provider verification were not run.
  The resolver change (unresolvable intrinsic invocation-member callee →
  `opaque`) is a deliberate semantic decision made during conflict resolution —
  reviewers should confirm it matches upstream's intended strictness, since
  upstream currently treats that shape as effect-free.
- `split/compatibility-first`: do not open a PR; the topic is fully upstream
  (PR #2122 and follow-ups). The fork branch exists only to record the
  verified-empty delta.
- Upstream moved fast during this work: base was pinned at
  `ca2d15b3ee965bd7ab27204cdf4b96b117d148c1` after re-fetch; re-verify if main
  advances again before PRs are opened.
