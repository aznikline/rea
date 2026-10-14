# REA-PR-REVIEW-CLOSURE-01 — review ledger

Scope: PR #2465 (`split/intrinsic-boundaries`), #2263 (`fix/webmcp-annotations`),
#2262 (`fix/inspect-signature-non-macho`) on `morluto/rea`. Compiled during
review-closure work; every "confirmed" claim cites an executed check at a pinned
SHA. `resolved`/`outdated` are GitHub thread flags — `resolved` reflects the
review tool state, not independent reviewer acceptance.

## Current heads (readback at ledger time)

| PR | Branch | HEAD at handoff | Current remote HEAD | Delta |
|---|---|---|---|---|
| #2465 | split/intrinsic-boundaries | `facc3547` | `c886eec6c` | maintainer fixes `ef8eb3ab1`, `e1253bede`, `e88b95608`, `e7dbe2492` + main merges + local `9ca6e6297` |
| #2263 | fix/webmcp-annotations | `273286fe` | `092a86cb4` | maintainer `cf136ee3b` + main merges + local `606e092a0`, `092a86cb4` |
| #2262 | fix/inspect-signature-non-macho | `f6f4cd79` | `f6f4cd79` | unchanged |

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
| **4262400691** | **P1: bound-alias write dropped — `invoke.call(change,...)` where `invoke = change.call`** | **YES — confirmed** | none yet | CI run `38447900942` on `c886eec6c`: this exact case fails in "Test shard (3/6)" and "Portable tests"; reproduces on clean local checkout (1 failed / 201 passed) | **unresolved** (reply 4266397011) |
| **4262492100** | **P1: canonical-depth miss for nested invocation reads (`ODP.apply.apply` after `Object.assign(FP.apply,{apply:poison})`)** | **not reproduced** | none | constructed counterexample per description returns correct `[]` at `c886eec6c`; equal-length cover-depth concern may hold internally but no observable misbehavior found | **unresolved** (reply 4266397717, honest non-confirmation) |
| **4262677516** | **P1: unknown argument-list suffix marked as fully-applied prefix (`make.apply(null,args)` with identifier args)** | **YES — confirmed** | none yet | counterexample added to the same it.each fails identically at `c886eec6c` (verification only, not committed) | **unresolved** (reply 4266397548) |

### Notes

- The destructuring P1 (`4258815795`) was fixed by the maintainer's
  evaluation-order model — explicit `childKeys` ordering (RHS before pattern,
  `["right","left","body"]` for `for…of`) plus per-leaf write retention and an
  `evaluationClock` — strictly better than a source-offset mask. A local
  alternative implementation (`a7b27a5db`, range-mask approach) was abandoned;
  do not reuse it.
- All three open P1s sit in `javascriptIntrinsicInvocation.ts` /
  `javascriptModuleInterop.ts` bound-invocation logic — the file the maintainer
  is actively rewriting. Fixes deferred to the maintainer line to avoid
  duplicating in-flight work (the destructuring collision already demonstrated
  this).
- CI at `c886eec6c`: run `38447900942` = **failure** — the only failing test is
  the `invoke.call(change,...)` bound-alias case (4262400691); "CI required",
  "Portable tests", "Test shard (3/6)" jobs failed on it. All other jobs pass or
  skip as usual.
- Abandoned local work: `a7b27a5db` (destructuring range-mask) — superseded,
  not on the remote branch.

## #2263 — fix/webmcp-annotations

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

## #2262 — fix/inspect-signature-non-macho

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

1. #2465: three open bound-invocation P1s (`4262400691` confirmed,
   `4262677516` confirmed, `4262492100` not reproduced) — no fix commit at
   `c886eec6c`; CI run `38447900942` red on the first one. Maintainer is
   actively iterating this file.
2. #2263: thread `4262599602` fix landed in `092a86cb4` and is awaiting thread
   resolution / CI on the new head.
3. #2262: green at `f6f4cd79`; awaiting maintainer merge decision only.

No PR was merged or closed by this work; statuses above are readback facts.
