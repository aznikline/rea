# REA-PR-REVIEW-CLOSURE-01 — review ledger

Scope: PR #2465 (`split/intrinsic-boundaries`), #2263 (`fix/webmcp-annotations`),
#2262 (`fix/inspect-signature-non-macho`) on `morluto/rea`. Compiled during
review-closure work; every "confirmed" claim cites an executed check at a pinned
SHA. `resolved`/`outdated` are GitHub thread flags — `resolved` reflects the
review tool state, not independent reviewer acceptance.

## Current heads (readback at ledger time)

| PR | Branch | HEAD at handoff | Current remote HEAD | Delta |
|---|---|---|---|---|
| #2465 | split/intrinsic-boundaries | `facc3547` | `21dfa5997` | maintainer fixes `ef8eb3ab1`, `e1253bede`, `e88b95608`, `e7dbe2492` + main merges + local `9ca6e6297`, `638a7f1ec`, `97fa50927`, `a13b93545` + merge `02ef51ab2` of `origin/main` `4135c911d` + `f3765f117` format fix + `1a866d496` (alias-write identity) + `025187d94` (destructured write context) + `a79c205a8` (captured-member owner validation + transitive aliases) + `989908c78` (replaced-member calls stay opaque) + `740977a3a` (wrapped default write timing) + `dbb05f06d` (Reflect.apply direct targets) + `ca1e2001a` (sequence-tail aliases) + `8e0853a84` (owner-key captured-member model) + `21dfa5997` (explicit-receiver preservation + destructured-read timing + shared member path helper) |
| #2263 | fix/webmcp-annotations | `273286fe` | `092a86cb4` (CLOSED, unmerged) | maintainer `cf136ee3b` + main merges + local `606e092a0`, `092a86cb4`; production absorbed upstream by `f6905719c` |
| #3837 | test/webmcp-invalid-annotations | — | `bcb92ebe3` | cherry-pick `092a86cb4` → `ff873c296` onto `4135c911d` + lint split `74e2dc324` + `bcb92ebe3` (own-property annotation override + null case) |
| #2262 | fix/inspect-signature-non-macho | `f6f4cd79` | **MERGED** `5eb296649` | upstream merge commit `5eb296649d2cd53b0bb74df7b3d8081e964e027d` |

## #2465 — split/intrinsic-boundaries

### Thread ledger

| Comment | Issue (root cause) | Exists at `c886eec6c`? | Fix commit | Validation | Thread state |
|---|---|---|---|---|---|
| 4255564424 | early-round review item | no | maintainer commits ≤ `e88b95608` | source inspection | resolved |
| 4258272796 | early-round review item | no | maintainer commits | source inspection | resolved |
| 4258272805 | early-round review item | no | maintainer commits | source inspection | resolved |
| 4258289734 | receiver loss / captured-function mutation (Codex, older) | no | maintainer commits ≤ `e88b95608` | covered by retained-write tests on current HEAD | resolved |
| 4258706117 | older unresolved at handoff | no | maintainer commits | same | resolved, outdated |
| **4258815795** | **P1: earlier destructuring-element write missed before later default-value call** | no — fixed | `ef8eb3ab1` (+ `e1253bede`, `e88b95608`): evaluation-order traversal via `childKeys`, per-leaf write retention, `evaluationClock` ordering | counterexample reproduced at `facc3547` (2 failing tests), then same counterexample green at `e88b95608`+; 36 intrinsic-capture tests pass | resolved, outdated |
| 4258906481 | early-round review item | no | maintainer commits | source inspection | resolved |
| 4258906489 | early-round review item | no | maintainer commits | source inspection | resolved, outdated |
| 4259400044 | early-round review item | no | maintainer commits | source inspection | resolved, outdated |
| 4260348579 | review item | no | maintainer commits | source inspection | resolved |
| 4260436913 | bound-invocation semantics (first wave) | no | maintainer commits incl. `e7dbe2492` | source inspection | resolved |
| 4260436918 | bound-member alias | no | maintainer commits | source inspection | resolved, outdated |
| **4261655637** | **unresolved merge-conflict markers committed by `d341d2eae` into `tests/process-global/cleanLinuxHopperRuntime.test.ts`** | no — fixed | `9ca6e6297` (local: kept incoming `assertCleanLinuxHopperRuntime` call, removed markers; also TS7022 `callable` annotation + lint-limit describe split) | `npm run check:fast` green at `9ca6e6297`; markers verified absent at merged `c886eec6c` | resolved, outdated (reply 4261760822) |
| 4261712627 | bound-invocation semantics (first wave) | no | maintainer commits | source inspection | resolved, outdated |
| **4262400691** | **P1: bound-alias write dropped — `invoke.call(change,...)` where `invoke = change.call`** | no — fixed | `638a7f1ec` (local): `capturedInvocationMember` follows the alias initializer's member read; read checked for contamination at its capture offset | CI run `38447900942` confirmed failure at `c886eec6c`; case now committed as regression test and passes at `638a7f1ec`; JS domain suite 1329/1329 | resolved (reviewer); fix replies 4266397011 + 4271064964 |
| **4262492100** | **P1: canonical-depth miss for nested invocation reads (`ODP.apply.apply` after `Object.assign(FP.apply,{apply:poison})`)** | no — fixed | `97fa50927` (local): `intrinsicReadChanged` checks a nested canonical read `[i,F,p,<prevInvMember>,method]`, covering equal-length `mutate-object` writes on `Function.prototype.*` | first counterexample (free `metadata`) did not reproduce; sharpened with provably-fresh `const metadata = {}` → failed at `c886eec6c`, passes at `97fa50927`; committed regression test; JS suite 1330/1330 | unresolved at fetch; correction reply 4271092502 after initial non-confirmation; re-review requested 4280465831 (fix intact at `025187d94`) |
| **4262677516** | **P1: unknown argument-list suffix marked as fully-applied prefix (`make.apply(null,args)` with identifier args)** | no — fixed | `638a7f1ec` (local): unknown `arguments_` now propagates instead of merging into `[]` | constructed counterexample reproduced failure at `c886eec6c`; case committed as regression test, passes at `638a7f1ec`; JS domain suite 1329/1329 | unresolved at fetch; fix replies 4266397548 + 4271065466; re-review requested 4280465501 (fix intact at `025187d94`) |
| **4271146564** | **P1: replaced outer invocation member erased window results — `invoke.call` re-read after `Function.prototype.call.call` replaced** | no — fixed | `a13b93545` (local): after the captured-member contamination check, the call-site read path `["intrinsic","Function","prototype","call",<method>]` (and `.apply` shape) is validated against writes before the callee's evaluation offset → `opaque` when replaced | reproduced via a `collectJavaScriptIdentityWritesSteps`-driven test at `97fa50927` (the write-free `invocationKinds` helper cannot observe read timing — earlier `browser_windows` was indistinguishable because a top-level opaque write also suppresses the finding); contrast set: unchanged `.call` still known+write retained, `.call`/`.apply` replaced → opaque + no `["i","O","create"]` write, argument-side effect retained exactly once; 40/40 capture tests, 1334/1334 JS domain at `a13b93545`, 1738/1738 post-merge `02ef51ab2`; `check:fast` green | resolved (reviewer); fix reply 4278859932 |
| **4278964125** | **P1: alias writes go missing — `invoke.call = () => {}` where `invoke = change.call` never reaches the captured-member identity** | no — fixed | `1a866d496` (local): shared `intrinsicInvocationMemberPath` (javascriptElectronMemberWrites.ts) computes the canonical `[i,F,p,<member>]` identity for both the resolver's `memberPath` and the new `capturedInvocationMemberPath` write-side fallback (javascriptModuleInterop.ts + semanticAnalysis origin) | reproduced at `f3765f117` — write dropped (no `[i,F,p,call,call]` in retained writes) → fixed: alias write lands on `[i,F,p,call,call]`/`[i,F,p,call,apply]`, the same slot as `Function.prototype.call.<m>`, invocation → opaque, no `["i","O","create"]`; unchanged-member control still known+write retained; 42/42 capture tests, 1742/1742 JS domain, `check:fast` + `oxfmt --check` green | resolved (reviewer); fix reply 4280459628 |
| **4278964129** | **P1: destructured write through reassigned alias loses assignment context — `[alias.URL] = […]` after `alias = {}` polluted `["global","URL"]`, hiding the Worker specifier** | no — fixed | `025187d94` (local): `retainTarget(leaf, effect, context)` — leaf remains the effect (per-leaf timing preserved) while the enclosing write site (assignment expr / for-of / for-in, mapped per leaf at pattern entry) is passed to `origin` as `writeSite`; `semanticMutationInitializers` now positions `for-in` like `for-of` | reproduced at `f3765f117` — Worker specifier `null` instead of `"./worker.js"` → fixed: `alias = {}` wins via `semanticMutationInitializers(binding, assignmentExpr)` → local write only; control with `alias` still `globalThis` still invalidates global URL (specifier `null`); destructuring-order tests (96-114) unaffected; 1742/1742 JS domain, `check:fast` green | resolved (reviewer); fix reply 4280461439 |
| **4280476067** | **P1: custom member aliases attributed to the intrinsic — `local.call = …` for `local = custom.call` wrote `[i,F,p,call,call]`, turning a later legitimate `FP.call.call` opaque** | no — fixed | `a79c205a8` (local): `capturedInvocationMember` requires the member owner to resolve to a provable callable (`intrinsicPath`/`boundIntrinsic`) | reproduced at `025187d94` — `[i,F,p,call,call]` retained for the custom alias → fixed: write dropped, trailing call stays `known`, window finding retained in public analysis; 45/45 capture, 1745/1745 JS domain | resolved (reviewer); fix reply 4289923344 |
| **4280540503** | **P1: owner-replaced member still canonicalized — `change.call = {call: noop}` before `invoke = change.call` made `Reflect.apply(invoke.call, …)` claim `Object.create`** | no — fixed | `a79c205a8` (local): same gate checks `intrinsicReadChanged(member, [ownerPath, key])` — the owner-specific slot must be unwritten at capture | reproduced at `025187d94` — `[i,O,create]` wrongly retained → fixed: no intrinsic write claimed; 1745/1745 JS domain | unresolved; fix reply 4289924888 |
| **4280540514** | **P1: copied captured-member alias broke the chain — `copy = invoke` left `copy.call(…)` with no retained effect, dropping the real write** | no — fixed | `a79c205a8` (local): `capturedInvocationMember` follows zero-projection identifier aliases transitively with a `visited` cycle guard | reproduced at `025187d94` — invocation `undefined`, write missing → fixed: `known` `defineProperty` + `[i,O,create]` retained; 1745/1745 JS domain | unresolved; fix reply 4289925054 |
| **4289940732** | **P1: replaced calls lost their effects — the owner-slot gate made `invoke.call(…)` after `change.call = () => {Object.create = …}` unrecognized (not opaque), dropping the unknown effect** | no — fixed | `989908c78` (local): `capturedInvocationMember` returns a tagged `CapturedInvocationMember` — `{member}` intact / `{replaced, path}` recognized-but-overwritten / `undefined` not-a-member; the resolver maps `replaced` → `opaque` at the owner-member path; `capturedInvocationMemberPath` yields a path only for intact members | test would-be-fail on `a79c205a8` (call unresolved, no effect) → fixed: `opaque` + `["intrinsic"]` effect retained, no confirmed `[i,O,create]`; 46/46 capture, 1746/1746 JS domain, `check:fast` green | resolved (reviewer); fix reply 4290019691 |
| **4290002429** | **P1: captured member passed directly as `Reflect.apply` target — `Reflect.apply(invoke, change, […])` rewrites the callee to the bare identifier, never consulting `memberRead`, so the real write was lost** | no — fixed | `dbb05f06d` (local): when `boundIntrinsic(callee)` fails and an explicit receiver exists, `memberRead` rewrites the callee to the captured member — the call/apply branch then resolves it like `invoke.call(…)`; bare `invoke(...)` still resolves to nothing; `replaced` → `opaque` | reproduced at `989908c78` — invocation `undefined`, write missing → fixed: `known` `defineProperty` + `[i,O,create]`; replaced-owner variant `opaque` + `["intrinsic"]`; 49/49 capture, 1749/1749 JS domain, `check:fast` green | unresolved; fix reply 4290090315 |
| **4290002438** | **P2: wrapped pattern writes retained before defaults — `[(change.call as any) = change.call(…)] = []` saw the leaf's parent as `TSAsExpression`, recording the write before the default ran and suppressing a valid window** | no — fixed | `740977a3a` (local): transparent-wrapper exits now own the leaf's timing (outermost wrapper is `AssignmentPattern.left`), the `AssignmentPattern` deferral check unwraps `left`, and the pattern child-order check unwraps too (covers wrapped nested patterns) | reproduced at `989908c78` — `browser_windows` suppressed → fixed: default call stays `known`, fresh-target write retained, window found; 49/49 capture, 1749/1749 JS domain, `check:fast` green | unresolved; fix reply 4290092247 |
| **4290078506** | **P1: sequence-tailed captured member aliases lost — `const invoke = (0, change.call)` hit the SequenceExpression branch and returned `undefined`, classifying `invoke.call(…)` as neither known nor opaque** | no — fixed | `ca1e2001a` (local): the alias walk peels `SequenceExpression` initializers to their tail (identifier tails continue the alias walk), matching the resolver's sequence-callee handling | reproduced at `dbb05f06d` — invocation `undefined`, write missing → fixed: `known` `defineProperty` + `[i,O,create]`; 50/50 capture, 1750/1750 JS domain, `check:fast` green | unresolved; fix reply 4290104526 |
| **4290159609** | **P1: bare call of a replaced captured member dropped — `invoke()` after `change.call = () => {Object.create = …}` ran the replacement but was classified `undefined` (not `opaque`)** | no — fixed | `8e0853a84` (local): `CapturedInvocationMember` remodeled as `{owner, key, at}` (+ `replaced` tag); the resolver substitutes the captured owner and processes the captured key as a virtual member read — a replaced captured callee stays `opaque` with a retained `["intrinsic"]` effect even without an explicit receiver | reproduced at `ca1e2001a` — bare call dropped entirely → fixed: `opaque` + `["intrinsic"]` effect, no confirmed `[i,O,create]`; 53/53 capture, 1753/1753 JS domain, `check:fast` + `oxfmt` green | unresolved; fix reply 4290295913 |
| **4290159616** | **P1: destructured invocation-member capture rejected — `const {call: invoke} = change` carries projection `["call"]`, which the zero-projection guard refused** | no — fixed | `8e0853a84` (local): exactly one static `call`/`apply`/`bind` projection resolves to the canonical member on the projected owner; the early `projection.length !== 0` rejection removed in favor of per-shape handling | reproduced at `ca1e2001a` — invocation unresolved → fixed: `known` `defineProperty` + `[i,O,create]`; 53/53 capture, 1753/1753 JS domain | unresolved; fix reply 4290296697 |
| **4290159619** | **P1: nested captured owner not provable — `const outer = invoke.call` where `invoke = change.call` needs the owner resolved through the captured-member path itself** | no — fixed | `8e0853a84` (local): `capturedInvocationMember` recurses (depth-bounded) so a captured member is itself a provable owner; the resolver's virtual-member view lets the substituted owner process the captured key as one more call level | reproduced at `ca1e2001a` — `outer.call(invoke, change, …)` unresolved → fixed: `known` `defineProperty` + `[i,O,create]`; 53/53 capture, 1753/1753 JS domain | unresolved; fix reply 4290297488 |
| **4290325648** | **P1: explicit receiver ignored under captured member — `Reflect.apply(invoke.call, noop, […])` substituted `captured.owner` (`change`) as callable, claiming a `Object.create` write that calls `noop` instead** | no — fixed | `21dfa5997` (local): the member call/apply branch keeps `callable = explicitReceiver ? receiver : memberObject` — owner substitution now applies only to the non-explicit path, where the alias identifier re-enters captured resolution anyway | reproduced at `8e0853a84` — `[i,O,create]` wrongly retained → fixed: no confirmed write; 55/55 capture, 1755/1755 JS domain | unresolved; fix reply 4290463430 |
| **4290325658** | **P1: destructured capture checks the member at the owner's earlier capture — `at = initializer.node` is the RHS identifier, which `intrinsicReadChanged` follows back to the bind call, missing `change.call = …` between bind and destructuring** | no — fixed | `21dfa5997` (local): projection captures run the slot write query inline at the destructuring evaluation offset (`writes` + `invocationMemberWriteCovers`, same predicate shape as the member branch incl. canonical + nested paths) | reproduced at `8e0853a84` — replaced `change.call` still yielded intact capture → `known` claimed → fixed: `replaced` → `opaque`, no `[i,O,create]`; 55/55 capture, 1755/1755 JS domain | unresolved; fix reply 4290463684 |
| **4290355683** | **P1: write through an invocation-member value not canonicalized — `change.call.call = noop` recorded `[i,O,defineProperty,call,call]`, so the call-site re-read of `[i,F,p,call,call]` missed the overwrite** | no — fixed | `111881cab` (local): the origin treats a member expression's value through `capturedInvocationMember` — intact → canonical `[i,F,p,<key>]` identity, `replaced` → no provable identity; `retainTarget`'s object identity now matches the read side | reproduced at `21dfa5997` — write landed on `[i,O,dP,call,call]`, later call stayed `known` → fixed: `[i,F,p,call,call]` retained, call `opaque`; 61/61 capture, 1761/1761 JS domain | unresolved; fix reply 4291062338 |
| **4290355688** | **P1: captured `bind` member dropped — `rebinder = change.bind; rebinder.call(change, …)` returned `undefined`, dropping the bound-callable continuation** | no — fixed | `111881cab` (local): `method === "bind"` unified — virtual (captured) and direct `x.bind` on a provable owner produce a known `[i,F,p,bind]` invocation with the bind target as `receiver`; replaced owner slots and a replaced `FP.bind` stay `opaque`; unprovable direct owners keep the prior unresolved classification | reproduced at `21dfa5997` — bound chain unresolved → fixed: `changed({value})` records `[i,O,create]`; 61/61 capture, 1761/1761 JS domain | unresolved; fix reply 4291062586 |
| **4290355695** | **P1: sequence-tail member owner not unwrapped — `(0, change).call(null, …)` never resolved the bound callable** | no — fixed | `111881cab` (local): `SequenceExpression` owners peeled to their tail in the resolver's member-object position and in `capturedInvocationMember` inputs | reproduced at `21dfa5997` — invocation unresolved → fixed: `known` `defineProperty` + `[i,O,create]`; 61/61 capture, 1761/1761 JS domain | unresolved; fix reply 4291062729 |
| **4290355697** | **P1: legitimate re-entry rejected by node-only cycle detection — `invoke.call(invoke, change, …)` revisits `invoke` under a different invocation state** | no — fixed | `111881cab` (local): `visited` keys on (callee id, receiver id, explicit-receiver flag, argument count, virtual member key@read node) instead of node identity; same-state cycles still fail closed | reproduced at `21dfa5997` — invocation `undefined`, write missing → fixed: `known` + `[i,O,create]`; 61/61 capture, 1761/1761 JS domain | unresolved; fix reply 4291062886 |
| **4290576830** | **P1: nested direct invocation member dropped — `change.call.call(change, …)` had `memberObject` a member expression that `memberRead` refused (identifiers only)** | no — fixed | `111881cab` (local): `capturedInvocationMember` accepts member expressions — owner/key read directly off the node, owner resolved through the same provable-callable chain (bound, intrinsic, or captured) | reproduced at `21dfa5997` — no effect recorded → fixed: `known` + `[i,O,create]`; 61/61 capture, 1761/1761 JS domain | unresolved; fix reply 4291063037 |
| **4290576840** | **P1: destructured capture timestamp at RHS owner, not the projected property read — `const {missing: x = (change.call = noop), call: invoke} = change` missed the default's write** | no — fixed | `111881cab` (local): `projectedCaptureAt` locates the `ObjectProperty` leaf for the projected key inside the declarator's `ObjectPattern`; `at` = that leaf, so the inline slot-write check evaluates at the property-read offset | reproduced at `21dfa5997` — replaced member captured intact → `known` claimed → fixed: `replaced` → `opaque`, no `[i,O,create]`; 61/61 capture, 1761/1761 JS domain | unresolved; fix reply 4291063182 |

### Notes

- The destructuring P1 (`4258815795`) was fixed by the maintainer's
  evaluation-order model — explicit `childKeys` ordering (RHS before pattern,
  `["right","left","body"]` for `for…of`) plus per-leaf write retention and an
  `evaluationClock` — strictly better than a source-offset mask. A local
  alternative implementation (`a7b27a5db`, range-mask approach) was abandoned;
  do not reuse it.
- All three second-wave bound-invocation P1s were fixed locally after remote
  activity paused: `638a7f1ec` (`capturedInvocationMember` alias substitution
  + unknown-argument propagation) and `97fa50927` (nested invocation-member
  read at canonical depth). Note: `4262492100` needed a provably-fresh
  `metadata` to reproduce — the free-identifier variant is suppressed by a
  different path and is not a valid counterexample.
- CI at `c886eec6c`: run `38447900942` = **failure** — the only failing test is
  the `invoke.call(change,...)` bound-alias case (4262400691); "CI required",
  "Portable tests", "Test shard (3/6)" jobs failed on it. All other jobs pass or
  skip as usual. CI on `97fa50927` was not started at ledger-update time.
- CI at `f3765f117`: run `38679888243` = **CI required + Portable tests pass**
  (reported by lead; this only proves the required lanes — not all platform
  shards ran). The two new P1s (`4278964125`, `4278964129`) were raised on that
  head anyway: they are coverage gaps in existing tests, not CI failures.
  CI on `025187d94` had not reported at ledger-update time.
- Abandoned local work: `a7b27a5db` (destructuring range-mask) — superseded,
  not on the remote branch.
- **Merge with main (`02ef51ab2`, base `4135c911d`)**: upstream evolved the
  write model independently — `origin` callback gained a `writeSite` parameter
  and member mutations are encoded as `[identity, null]` unknown-child paths
  under `SemanticPropertyPathCoverage` (no `kind` field upstream). Resolution
  kept the branch's evaluation-clock / pattern / exit-time call machinery and
  `kind`-tagged `retainWrite`, adopted the `writeSite` signature and the
  `[null]` encoding, and updated `invocationMemberWriteCovers` so a
  `mutate-object` write is scoped by its trailing `null` segment rather than a
  length-minus-one rule. Post-merge: 1738/1738 JS domain tests, `check:fast`
  green; ``mergeable` readback MERGEABLE at `02ef51ab2`; `f3765f117` fixes a `format:check` failure (oxfmt on merged `fridaLifecycleMcp.test.ts`).
- **Author declaration: `HUMAN_ATTESTATION_REQUIRED`.** The
  `Validate author declaration` check (workflow `pr-readiness.yml`, script
  `scripts/ci/pr-readiness.mjs`) reads the PR **body**: exactly one
  `Human owner: @handle` line plus all three template declarations checked.
  The body previously lacked the `## Author readiness` section entirely; the
  skeleton (placeholder owner, unchecked boxes) is now present so the check
  still correctly fails until the human owner completes it. Agent did not and
  must not fill the handle or check the boxes.
- `mergeStateStatus` = `BLOCKED` at `02ef51ab2` — the readiness declaration is
  the remaining blocker; Greptile "success" on earlier runs only means the
  review completed (it raised 4271146564).

## #2263 — fix/webmcp-annotations (CLOSED, production absorbed upstream)

- PR closed unmerged (GitHub state); production behavior absorbed by upstream
  `f6905719c3c80d829037e509d6e46129b131d893` ("Reviewed fixes: #2263").
  `consequential` retention and `invalid_protocol_value` handling verified
  present on `origin/main` `4135c911d`.
- Test patch `092a86cb4` was **not** absorbed: main covers only boolean
  `consequential` (`it.each([true,false])`) and lacks the `webMcpAnnotations`
  fixture override. Minimal test-only follow-up prepared on branch
  `test/webmcp-invalid-annotations` (`ff873c296` cherry-pick + `74e2dc324`
  lint-split) → **PR #3837** (open, non-draft at readback).

### Thread ledger

| Comment | Issue | Exists at `092a86cb4`? | Fix commit | Validation | Thread state |
|---|---|---|---|---|---|
| 4255520404 | early-round item | no | maintainer commits | source inspection | resolved |
| 4258281898 | P1: missing `consequential` in old capture reported as change | no | maintainer commits (`webMcpDimension` unknown-hint projection) | verified at `606e092a0`: unknown-hint pairs → `unknown`, real changes → `changed`; 19/19 boundary tests | resolved (reply 4266361039) |
| 4258281914 | P1: invalid protocol value treated as undeclared | no | maintainer commits (boolean check + `invalid_protocol_value`) | verified at `606e092a0` | resolved, outdated (reply 4266362210) |
| 4258648361 | genuine comparison-branch tests required | no | `cf136ee3b` (maintainer): missing-either-side, true→false, missing+other-change matrix | 19/19 `webCaptureDiff.test.ts` pass at `606e092a0` | resolved, outdated |
| 4258662870 | doc wrongly claims missing field = legacy only | no | `cf136ee3b`: doc now covers invalid-current-value path | doc diff inspected | resolved, outdated |
| 4259281855 | review item | no | maintainer commits | source inspection | resolved, outdated |
| 4259300953 | review item | no | maintainer commits | source inspection | resolved, outdated |
| **4262599602** | **P2: invalid-annotation branches lack browser-level tests** | no — fixed | `092a86cb4` (local): it.each over non-boolean `consequential` + malformed `annotations`; asserts retained registration, omitted `consequential`, `invalid_protocol_value` exclusion + `unavailable_sections` | 28/28 `cdpBrowserProvider.document_script.test.ts`, 47/47 combined; `check:fast` clean | unresolved at fetch; fix reply 4266390632 |

### Local commits on this branch

- `606e092a0` `fix(ci): split WebMCP emit and diff describes under the lint limit`
- `092a86cb4` `test(browser): cover invalid WebMCP annotation payloads`

### CI

- `aec3226ef` run `38448138783`: **failure** — Static checks + CI required, two
  `max-lines-per-function` lint errors (the ones `606e092a0` removed).
- `092a86cb4`: **no CI run started yet** at ledger time; check rollup still
  shows the stale `aec3226ef` failures.

## #3837 — test/webmcp-invalid-annotations

| Comment | Issue | Exists at `74e2dc324`? | Fix commit | Validation | Thread state |
|---|---|---|---|---|---|
| **4279727743** | **P2: explicit `webMcpAnnotations: null` replaced by valid defaults — fixture `??` treated null as absent** | no — fixed | `bcb92ebe3` (local): `Object.hasOwn(options, "webMcpAnnotations")` selects the override by presence; `null` case added to the invalid-payload `it.each` | null case fails against the pre-fix fixture, passes after; asserts retained registration, no fabricated `consequential`, `invalid_protocol_value` + `unavailable_sections`; 29/29 boundary tests, `check:fast` + `oxfmt --check` green | resolved (reviewer); fix reply 4280463497 |

- No production provider change; boolean `consequential` and omitted-annotation
  defaults unchanged. Author readiness: `HUMAN_ATTESTATION_REQUIRED` — skeleton
  present, human owner must complete. CI on `bcb92ebe3` not yet reported at
  ledger time.

## #2262 — fix/inspect-signature-non-macho (MERGED)

- Merged upstream at merge commit `5eb296649d2cd53b0bb74df7b3d8081e964e027d`
  (2026-10-13 21:22:43 UTC+08). Both review threads resolved before merge.
  No further action; branch may be deleted when convenient.

| Comment | Issue | Exists at `f6f4cd79`? | Fix commit | Validation | Thread state |
|---|---|---|---|---|---|
| 4255520421 | capability advertised but operation refused | no | `f6f4cd79` (maintainer): `MACHO_TARGET_OPERATIONS` + description | source inspection | resolved |
| 4258260432 | same root cause (duplicate) | no | `f6f4cd79` | source inspection | resolved |

- HEAD unchanged since review; no production-code modification by this line.
- CI run `38396465232` on `f6f4cd79`: **completed/success** — 24 jobs pass,
  18 skipped (platform/release lanes).
- New-HEAD local validation: **NOT_RUN** (out of authorized scope; historical
  test evidence predates `f6f4cd79`).

## Outstanding at ledger close

1. #2465 (`111881cab`): eighth wave — six P1s (`4290355683`,
   `4290355688`, `4290355695`, `4290355697`, `4290576830`, `4290576840`)
   covering write canonicalization, captured `bind`, sequence owners,
   state-keyed cycle detection, nested member reads, and destructured
   read timing — all reproduced at `21dfa5997`, fixed, replied; awaiting
   reviewer. Seventh-wave `4290325648`/`4290325658` fixed in `21dfa5997`;
   sixth-wave `4290159609`/`4290159616`/`4290159619` in `8e0853a84`;
   `4280540503`/`4280540514`, `4290002429`/`4290002438`/`4290078506`,
   `4262492100`/`4262677516` likewise unresolved with fixes in place.
   `mergeable_state` readback: `blocked` (Author readiness placeholders;
   CI re-running on `111881cab`).
   CI on `8e0853a84` (run `38841115324`): Static checks failed on `knip` —
   the `8e0853a84` refactor left `intrinsicInvocationMemberPath` an unused
   export; fixed in `21dfa5997` by reworking it to a key-parameterized
   helper shared by all canonical member-path sites. Test failures in the
   same run are unrelated flakes: Source tests = `PlaywrightBrowserScenarioProvider`
   cancellation timing (`AnalysisCancelledError`, same flake as `a79c205a8`
   run `38834492640`); Test shard (2/5) = `browserScenarioProbeLifecycle`
   shared-provider discovery-probe assertion — no intrinsic-invocation test
   failed.
2. #3837 (`bcb92ebe3`): P2 `4279727743` fixed (`Object.hasOwn` override +
   null case) and the thread is **resolved**; `mergeable_state` `clean`.
   Same `HUMAN_ATTESTATION_REQUIRED` on author readiness.
3. #2263: closed unmerged; production absorbed upstream (`f6905719c`).
   Remaining test coverage carried by #3837.
4. #2262: **MERGED** `5eb296649` — done.

No PR was merged or closed by this work; statuses above are readback facts.
