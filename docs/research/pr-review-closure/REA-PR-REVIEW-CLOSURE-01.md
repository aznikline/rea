# REA-PR-REVIEW-CLOSURE-01 — review ledger

Scope: PR #2465 (`split/intrinsic-boundaries`), #2263 (`fix/webmcp-annotations`),
#2262 (`fix/inspect-signature-non-macho`) on `morluto/rea`. Compiled during
review-closure work; every "confirmed" claim cites an executed check at a pinned
SHA. `resolved`/`outdated` are GitHub thread flags — `resolved` reflects the
review tool state, not independent reviewer acceptance.

## Current heads (readback at ledger time)

| PR | Branch | HEAD at handoff | Current remote HEAD | Delta |
|---|---|---|---|---|
| #2465 | split/intrinsic-boundaries | `facc3547` | `02ef51ab2` | maintainer fixes `ef8eb3ab1`, `e1253bede`, `e88b95608`, `e7dbe2492` + main merges + local `9ca6e6297`, `638a7f1ec`, `97fa50927`, `a13b93545` + merge `02ef51ab2` of `origin/main` `4135c911d` + `f3765f117` format fix |
| #2263 | fix/webmcp-annotations | `273286fe` | `092a86cb4` (CLOSED, unmerged) | maintainer `cf136ee3b` + main merges + local `606e092a0`, `092a86cb4`; production absorbed upstream by `f6905719c` |
| (follow-up) | test/webmcp-invalid-annotations | — | `74e2dc324` | cherry-pick `092a86cb4` → `ff873c296` onto `4135c911d` + lint split `74e2dc324`; draft PR #3837 |
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
| **4262400691** | **P1: bound-alias write dropped — `invoke.call(change,...)` where `invoke = change.call`** | no — fixed | `638a7f1ec` (local): `capturedInvocationMember` follows the alias initializer's member read; read checked for contamination at its capture offset | CI run `38447900942` confirmed failure at `c886eec6c`; case now committed as regression test and passes at `638a7f1ec`; JS domain suite 1329/1329 | unresolved at fetch; fix replies 4266397011 + 4271064964 |
| **4262492100** | **P1: canonical-depth miss for nested invocation reads (`ODP.apply.apply` after `Object.assign(FP.apply,{apply:poison})`)** | no — fixed | `97fa50927` (local): `intrinsicReadChanged` checks a nested canonical read `[i,F,p,<prevInvMember>,method]`, covering equal-length `mutate-object` writes on `Function.prototype.*` | first counterexample (free `metadata`) did not reproduce; sharpened with provably-fresh `const metadata = {}` → failed at `c886eec6c`, passes at `97fa50927`; committed regression test; JS suite 1330/1330 | unresolved at fetch; correction reply 4271092502 after initial non-confirmation |
| **4262677516** | **P1: unknown argument-list suffix marked as fully-applied prefix (`make.apply(null,args)` with identifier args)** | no — fixed | `638a7f1ec` (local): unknown `arguments_` now propagates instead of merging into `[]` | constructed counterexample reproduced failure at `c886eec6c`; case committed as regression test, passes at `638a7f1ec`; JS domain suite 1329/1329 | unresolved at fetch; fix replies 4266397548 + 4271065466 |
| **4271146564** | **P1: replaced outer invocation member erased window results — `invoke.call` re-read after `Function.prototype.call.call` replaced** | no — fixed | `a13b93545` (local): after the captured-member contamination check, the call-site read path `["intrinsic","Function","prototype","call",<method>]` (and `.apply` shape) is validated against writes before the callee's evaluation offset → `opaque` when replaced | reproduced via a `collectJavaScriptIdentityWritesSteps`-driven test at `97fa50927` (the write-free `invocationKinds` helper cannot observe read timing — earlier `browser_windows` was indistinguishable because a top-level opaque write also suppresses the finding); contrast set: unchanged `.call` still known+write retained, `.call`/`.apply` replaced → opaque + no `["i","O","create"]` write, argument-side effect retained exactly once; 40/40 capture tests, 1334/1334 JS domain at `a13b93545`, 1738/1738 post-merge `02ef51ab2`; `check:fast` green | unresolved; fix reply 4278859932 |

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
  lint-split) → **draft PR #3837**; 28/28 boundary tests + `check:fast` green.

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

1. #2465 (`f3765f117`): all second-wave P1s + new P1 `4271146564` fixed
   (`638a7f1ec`, `97fa50927`, `a13b93545`) with committed regression tests and
   evidence replies; main `4135c911d` merged in (`02ef51ab2`), `mergeable`
   readback MERGEABLE. Remaining blocker: **Author readiness —
   `HUMAN_ATTESTATION_REQUIRED`** (skeleton added to PR body; human owner must
   fill `Human owner: @handle` and check the three declarations). Awaiting
   reviewer thread resolution and CI on `f3765f117`.
2. #2263: closed unmerged; production absorbed upstream (`f6905719c`).
   Remaining test coverage carried by draft PR #3837 (branch
   `test/webmcp-invalid-annotations` @ `74e2dc324`).
3. #2262: **MERGED** `5eb296649` — done.

No PR was merged or closed by this work; statuses above are readback facts.
