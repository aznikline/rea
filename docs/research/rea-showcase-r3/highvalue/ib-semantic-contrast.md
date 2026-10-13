# intrinsic-boundaries: semantic contrast and gate results

Date: 2026-10-13
Upstream base: `ca2d15b3ee965bd7ab27204cdf4b96b117d148c1`
(base/head comparison executed on `origin/main` `f254f5ac2b804b353a711264bb178f43fdf07867`,
one unrelated android commit past the base, in scratch worktree
`/Users/wizout/op/rea-wt-ib-base`)
Candidate: `split/intrinsic-boundaries` HEAD `8d5e11efcdc3e346f78d9dc3901693de7a4b3445`
(`85ad41e55` fix commit + `8d5e11efc` semantic-contrast tests and wording),
pushed to fork remote only.

## Reviewer correction absorbed

The motivating example `const change = Object.defineProperty.call; change(...)`
reads `Function.prototype.call` itself. Invoked bare, a real engine evaluates
the argument expressions and then throws `TypeError: Function.prototype.call
was called on undefined, which is undefined and not a function` (verified on
Node v26). No property write executes. `opaque` in the candidate therefore
means "cannot determine call identity/effects" — conservative unknown — NOT
"confirmed write occurred". Argument-side effects must still be recorded
because arguments evaluate before the throw.

Upstream `9d8e42bdd` (#1912) is NOT characterized as a proven regression. The
accurate description: after #1912, an identifier bound to an intrinsic
invocation member read (`const change = Object.defineProperty.call;
change(...)`) resolved to a `*.call`/`*.apply` path but derived no callable,
so the resolver returned `undefined` — leaving identifier-aliased intrinsic
invocation member reads effect-free. Concrete failing input:

```js
const change = Object.defineProperty.call;
change(null, Object, "create", { value: customCreate });
```

On the base this call retained no write effect, so the following Rolldown
`__toESM` conversion kept `Object.create`/`Object.defineProperty` identity and
the converted `new electron.BrowserWindow({})` was reported.

## Semantic table (runtime vs analyzer)

| # | Input (all followed by ROLLDOWN `__toESM` interop + `require("electron")` + `new electron.BrowserWindow({})`) | Runtime behavior | Base (`f254f5ac2`) | Candidate (`8d5e11efc`) |
|---|---|---|---|---|
| 1 | `const change = Object.defineProperty.call; change(null,Object,"create",{value:customCreate});` | args eval, then TypeError; no write | resolver `undefined` (effect-free) → windows 1 (unsound over-report) | `opaque` `intrinsic.Object.defineProperty.call` → windows 0 |
| 2 | `const {apply:change} = Object.defineProperty; change(null,[Object,"create",{value:customCreate}]);` | args eval, then TypeError | `undefined` → windows 1 | `opaque` `intrinsic.Object.defineProperty.apply` → windows 0 |
| 3 | `const change = Reflect.apply.call; change(null,Object.defineProperty,null,[Object,"create",{value:customCreate}]);` | args eval, then TypeError | `undefined` → windows 1 | `opaque` `intrinsic.Reflect.apply.call` → windows 0 |
| 4 | `const change = Object.defineProperty.call; change.call(Object.defineProperty,null,Object,"create",{value:customCreate});` | real write (`Object.create` replaced, verified) | `known` `intrinsic.Object.defineProperty` → windows 0 | identical |
| 5 | `Function.prototype.call.call(Object.defineProperty,null,Object,"create",{value:customCreate});` | real write | `known` → windows 0 | identical |
| 6 | `(0, Object.defineProperty)(Object,"create",{value:customCreate});` | real write (sequence callee selects defineProperty) | `undefined` → windows 1 (missed write; unsound over-report) | `known` `intrinsic.Object.defineProperty` → windows 0 |
| 7 | `const metadata = {}; Object.defineProperty.call(null,metadata,"x",{value:1});` | write to fresh `metadata` only | `known` → windows 1 | identical |
| 8 | `Object.defineProperty.call = replacement; const change = Object.defineProperty.call; change(null,Object,"create",{value:customCreate});` | `replacement(...)` runs — identity unknown to analyzer | `undefined` → windows 0 (opaque via replaced bound capture — right outcome, different mechanism) | `opaque` → windows 0 |
| 9 | `Object.defineProperty.call = replacement; const change = Object.defineProperty.call; change.call(Object.defineProperty,null,Object,"create",{value:customCreate});` | `replacement.call(...)` runs — unknown | `known`→(replaced bound capture → opaque at call) → windows 0 | resolver-only probe `known`; workflow retains the member write → `opaque` → windows 0 |
| 10 | `const change = Object.defineProperty.call; change((Object.create = replacement, null),Object,"create",{value:customCreate});` | arg replaces `Object.create`, then TypeError | arg write recorded (`enter` traversal) → windows 0 | `opaque` + arg write → windows 0 |
| 11 | `const {apply:change} = Object.defineProperty; change(null,[(Object.defineProperty = replacement, Object),"create",{value:customCreate}]);` | arg replaces `Object.defineProperty`, then TypeError | arg write recorded → windows 0 | `opaque` + arg write → windows 0 |
| 12 | `const change = Object.defineProperty.call; change(null,Object,"create",{value:new (require("electron").BrowserWindow)({})});` | arg constructs window, then TypeError | windows 2 (outer window over-reported too) | `opaque` outer call; argument finding retained → windows 1 |
| 13 | control (no mutation) | normal | windows 1 | windows 1 |

Fields recorded per case: resolver `kind`+`path` (module boundary via
`createSemanticModuleInterop(state).intrinsicInvocation`), `browser_windows`
count + `options_status`, `ipc`/`context_bridge_apis` counts, `parse_status`,
`parse_error_count`, `visited_ast_nodes`, `limitations`. All cases report
`parse_status: "complete"` with identical limitation strings on both sides —
no coverage/unknown field distinguishes "dropped result" from "conservative
handling"; the semantic contrast lives in the resolver `kind` and the finding
counts. That is expected: `ELECTRON_IDENTITY_LIMITATION` already declares that
missing findings do not establish absence.

### Base/head deltas (the only rows that differ)

- Cases 1–3: base `unresolved`/effect-free → head `opaque`. windows 1 → 0.
- Case 6 (`(0, Object.defineProperty)`): base `unresolved` → head `known`.
  windows 1 → 0. This is the strongest delta: the sequence callee performs a
  real, verified write at runtime that base dropped entirely — a missed write,
  not merely a conservatism gap.
- Case 12 (`arg-finding`): base windows 2 → head windows 1. Base over-reported
  the interop-converted window because the opaque call effect was dropped; the
  argument's own `require("electron").BrowserWindow` finding is correctly
  retained on both sides.
- Cases 8–9 (replaced member): windows identical, but mechanism differs — base
  only reached `opaque` through the replaced bound-capture path, head also
  marks the bare alias invocation opaque directly.

### Tests added (candidate commit `8d5e11efc`)

`src/domain/javascript/electronIntrinsicCapture.test.ts` gains
`describe("identifier-aliased intrinsic invocation members")` — 11 new tests
(file total 20, all passing):

- bare `.call`/`.apply`/`Reflect.apply.call` alias invocations (the TypeError
  cases): assert resolver `kind === "opaque"` — explicitly neither effect-free
  nor a confirmed write — and `browser_windows` dropped.
- resolvable callable receivers (`change.call(Object.defineProperty, ...)`,
  `Function.prototype.call.call(...)`, `(0, Object.defineProperty)(...)`):
  assert `kind === "known"` with path `intrinsic.Object.defineProperty` —
  direct contrast that opaque is not the universal outcome.
- known invocation limited to a fresh target keeps the window (1).
- replaced invocation member read: same call resolves `known` before the
  member write is retained, `opaque` after — isolating the replaced-read route.
- argument-expression writes (`Object.create = replacement` inside the
  argument of a throwing bare alias) recorded alongside the opaque call.
- findings inside an opaque call's argument (`new (require("electron").BrowserWindow)({})`)
  still produce a `browser_windows` finding.

## `npm run check:pr`

Command: `npm run check:pr` in `/Users/wizout/op/rea-wt-split-ib`
(precheck deps:check, turbo `typecheck lint:built format:check knip
metadata:check test:run`, then `test:python`, `docs:check`, `jscpd`,
`scan:todos`). Duration 25m45s for the turbo phase.

Result: `test:run` exited 1 — **7 failed tests in 5 files out of 10,346**
(10,124 passed, 215 skipped, 5 files failed / 1005). All seven are
host-environment real-toolchain lanes, and every one was reproduced
identically on the base worktree (`f254f5ac2`, unmodified upstream) via
`npm run test:focused`:

| Failed test | Failure | Verified on base |
|---|---|---|
| `tests/acceptance/providers/hopperStartupRecovery.test.ts` › denial-shaped failure | `Hopper application bridge could not be started` / ENOENT realpath `loader-target` (72s) | identical |
| `tests/boundary/cli/hopperLaunchFailureCli.test.ts` › retained-cleanup retry | same ENOENT Hopper bridge launch (64s) | identical |
| `tests/boundary/process/darwinProcessRunTokenReader.test.ts` (3 tests) | 30s timeouts: Swift-helper compile, NUL-token parse, ENOMEM sysctl retry | identical (3/3) |
| `tests/boundary/process/processSettlementDeadline.test.ts` › observed liveness | `live fixture group never observed as alive` | identical |
| `tests/boundary/providers/native/machoSliceReader.test.ts` › /bin/ls FAT table | `lipo slice metadata disagrees with the Mach-O FAT table` | identical |

None touches the JavaScript analyzer; the candidate's own lanes all pass,
including `tests/acceptance/applications/electronModuleInteropCli.test.ts`
(2 tests, CLI + stdio MCP) inside `test:run`. typecheck, lint:built,
format:check, knip, metadata:check all passed. The `&&`-chained steps after
`test:run` did not execute within check:pr and were run separately on the
candidate: `test:python` OK (9+11 tests), `docs:check` OK, `jscpd` OK
(2.98% duplicated lines, under the 3% limit), `scan:todos` OK (no markers).

## Production CLI/MCP static entry (harmless target, no execution)

Target: `/tmp/rea-fake-app` — minimal fake Electron app
(`package.json` main=`main.cjs`, inert `preload.js`, `main.cjs` containing the
bare-alias counter-example + Rolldown `__toESM` interop + `require("electron")`
+ `new electron.BrowserWindow({webPreferences:{preload:"./preload.js"}})`).
A real ASAR was packed with `@electron/asar` `createPackage` →
`/tmp/rea-fake-app.asar`. Control app `/tmp/rea-fake-app-ctrl` is identical
minus the two alias lines. No target code executed; static input only.

Commands + results:

- `REA_LOG_LEVEL=silent node scripts/rea.mjs analyze-javascript-application /tmp/rea-fake-app --format json`
  (candidate): exit 0, `parse_failures: 0`, `findings: 3`,
  `browser-window` nodes: **0** — the opaque call invalidates the interop
  conversion, so the window is conservatively unreported. `electron-preload`
  role still resolved (syntax-level role path).
- Same command on `/tmp/rea-fake-app.asar`: exit 0, `browser-window` nodes: 0,
  `asar-entry` nodes: 3 — real ASAR container path exercised.
- `REA_LOG_LEVEL=silent node scripts/rea.mjs analyze /tmp/rea-fake-app --format json`:
  exit 0, routed to `analyze_javascript_application`, same 0 window nodes.
- Control app (candidate): `browser-window` nodes: **1**, findings 4 — pipeline
  intact; the missing node on the mutated app is the conservative result, not
  a harness artifact.
- BASE worktree CLI (`rea-wt-ib-base`, dist built via `npm run build:cached`)
  on the mutated app: `browser-window` nodes: **1**, findings 4 — base
  over-reports at the production boundary exactly as the domain comparison
  predicts.

## Remaining gates

- PR not opened; nothing merged; nothing pushed to origin. Fork branch updated
  (`85ad41e55..8d5e11efc`, no force; pre-push `check:fast` passed).
- `check:pr` is NOT green in this environment: 7/10,346 tests fail, all
  host-environment real-toolchain lanes (Hopper bridge launch, Swift-helper
  compile, Darwin process liveness, system lipo). Each was reproduced
  identically on the unmodified base — none is attributable to the candidate.
  A maintainer with a provisioned macOS lane should re-run `check:pr` (or CI)
  to confirm.
- Base scratch worktree `/Users/wizout/op/rea-wt-ib-base` (detached at
  `f254f5ac2`, `npm ci` + `npm run build:cached` done) can be removed after
  review.
- No real-provider execution lanes were required: the change is static
  JavaScript analysis only; the production-entry check used an inert
  directory/ASAR input.
