# Fork branch audit — aznikline/rea

All branches pushed to `fork` (ssh://git@ssh.github.com:443/aznikline/rea.git)
for remote archival and independent review. **Push ≠ upstream-merge
approval.** `origin/main` at audit time: `d96550f2f61647ffa150597de73363fa90c4e169`.
Sensitive-content scan of new reachable history (binary files, secret-like
strings, user paths): clean — see notes below.

## Branch table

| Branch | REMOTE_EXACT_SHA | Merge-base w/ origin/main | Contents | Status |
|---|---|---|---|---|
| `research/showcase-r3` | `1522d8383ca2fe87c887031f45d5c5c24ff492d3` | `974f11d01` | this evidence program's docs only | evidence record |
| `fix/webmcp-annotations` | `354ec7cee` (post-doc-fix; fix itself `449c58a37`) | `974f11d01` | `consequential` fidelity fix + tests + browser-observation prereq docs | **Draft PR opened: morluto/rea#2263** |
| `fix/inspect-signature-non-macho` | `028054116` | `d96550f2f` | minimal gate fix cherry-picked from `120c2769a` onto current main, corrected comment | **Draft PR opened: morluto/rea#2262** |
| `integration/feat/pkg-inventory` | `120c2769a5489906f52add62d14c5f3d8be3ced0` | `538f8cc72` | feat/pkg-inventory merge + `120c2769a` gate fix | merge snapshot held; gate fix → **Draft-PR candidate (B)** |
| `integration/high-value` | `1502a9b0198bd043535364595bf08d04ad9f445c` | `538f8cc72` | merge of `feat/compatibility-first-analysis-20261012` (`d4faf3931`) + `codex/fix-intrinsic-invocation-boundaries` (`1502a9b01`) | integration snapshot; NOT an upstream PR package |
| `integration/feat/signature-posture` | `4c0e06583be51c679651771f1cfedaddf92cb8f7` | `538f8cc72` | feat/signature-posture merge (`c3450b1bf`) + lint fix (`4c0e06583`) | review candidate — see gates |
| `integration/feat/dyld-shared-cache` | `4b34bc001f6478e5870ce683d1aede90726ba24d` | `538f8cc72` | feat/dyld-shared-cache merge (incl. amended envelope fixup) | review candidate — not audited this round |

Dependency note: all three `integration/feat/*` and `integration/high-value`
branches merge side-branch work onto `538f8cc72`-era main; they share the
old `feat/artifact-integrity-policy` lineage already absorbed by main. They
are mutually independent merge snapshots — none depends on another's
commits.

## Test evidence per branch

| Branch | Verification (from R2 merge work / this round) |
|---|---|
| `integration/high-value` | `npx tsc --noEmit` 0 err; 231 tests (cli+mcp analysis-view + electron intrinsic/module-interop); lint warnings only |
| `integration/feat/pkg-inventory` | tsc 0; 68 pkg tests; this round: 78/78 native boundary + check:fast |
| `integration/feat/signature-posture` | tsc 0; ~111 signature/posture/codesign tests; pre-push check:fast passed after `4c0e06583` |
| `integration/feat/dyld-shared-cache` | tsc 0; ~231 dyld/apple-domain/dylib-MCP tests |
| `fix/webmcp-annotations` | tsc clean; touched-lane tests + oxlint + module-boundaries; real zapier.com Evidence round-trip `ev_e451abd5…` |
| `research/showcase-r3` | docs only — no code verification applies |

## Remaining gates (before any upstream proposal)

- `integration/high-value`: split into reviewable units (compatibility-first
  vs intrinsic-boundaries are independent changes); confirm no regression
  vs current main (`d96550f2f`).
- `integration/feat/signature-posture`: resolve `verification.status:"unknown"`
  vs definitive codesign-rejection mapping (`CodesignVerification.ts`
  INVALID_SIGNATURE_REASONS) — under-report confirmed by InstallerAlert
  oracle; plus the same pkg-gate issue fixed only on pkg branch.
- `integration/feat/dyld-shared-cache`: no independent review this round;
  needs dedicated audit before any upstream proposal.
- `integration/feat/pkg-inventory`: inventory drops XAR `<signature>`;
  pbzx/member limitations don't aggregate to top-level coverage;
  Distribution/PackageInfo no semantic parse — coverage contract +
  regression tests needed before review.

## Scan notes

- `integration/high-value` contains `experiments/analysis-efficiency/`
  corpus + result JSONs — public-artifact manifests (ShareX.dll sha256,
  provenance), no binaries, no user paths.
- `integration/feat/dyld-shared-cache` "libsecret.dylib" hits are test
  fixture names only.
- No credentials, application bundles, malware payloads, or unsanitized
  captures found in new reachable history.
