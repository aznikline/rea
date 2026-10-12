# REA `.pkg` correctness audit — signature classification and inventory coverage

Scope: worktree `/Users/wizout/op/rea-wt-pkg` (`integration/feat/pkg-inventory`, base `702dfb351`, fix commit `120c2769a`), plus `inspect_signature` comparison from `/Users/wizout/op/rea-wt-sig`. All analysis non-executing; no payload scripts or malware binaries were run. Fixtures live under `/tmp/rea-r3-pkg/` (not committed); oracle text under `/Users/wizout/op/targets/versus-pkg/oracle/`.

## 1. Classification path (file:line evidence)

A `.pkg` input resolves as an **archive** target:

- `src/application/BinaryTargetResolver.ts:291-296` — `.pkg` suffix + `xar!` magic → `format: "pkg"`; `:180-182` → `kind: "archive"`.
- `src/cli/utilityCommands.ts:152` — `rea inspect-signature` maps to operation `inspect_signature`.
- `src/native/NativeMacOSProvider.ts` — `NativeMacOSProvider` is a macOS **auxiliary** provider (`src/composition/auxiliaryAnalysisProviders.ts:38-40`), so `inspect_signature` is reachable for archive targets.
- `#dispatch` routes `inspect_signature` → `#inspectSignature` (`NativeMacOSProvider.ts:447-448`), which snapshots the file (`withSignatureTarget`, `SignatureTargetBinding.ts:69-106`) and runs `codesign -d --verbose=4`, `-d -r-`, `-d --entitlements :-` on the byte snapshot (`#captureSignature`, former `NativeMacOSProvider.ts:671-705`).
- `isNonzeroUnsignedObservation` (former `NativeMacOSProvider.ts:969-972`) classifies exit≠0 + `/not signed at all|code object is not signed/` as unsigned; `parseCodeSignature` (`src/native/parsers/codesign.ts:40,52`) then emits `signed: false` with limitation `"Artifact is not signed."`.

**There was no format gate on `inspect_signature`** (contrast `inspect_macho`/`list_architectures`, which reject non-Mach-O targets at `NativeMacOSProvider.ts:463-470` and `:791-797`).

XAR-level signatures are invisible to this path **and** to the inventory path:

- `src/artifacts/XarArtifactReader.ts` `#verifyToc` (`:562-628`) reads only `<toc><checksum>`; `collectMembers` (`:229-276`) collects only `<file>` children. A `<signature>` TOC element — which carries the package signature style, heap offset/size, and `KeyInfo` certificates — is silently dropped. No signature observation exists anywhere in the pkg pipeline (grep over `src/artifacts/`, `src/domain/artifactGraph.ts`).

So **before the fix**, `rea inspect-signature x.pkg` always reported `signed:false` / `"Artifact is not signed."` for any pkg — unsigned, validly signed, or invalidly signed — because `codesign -d` cannot evaluate the xar layer.

## 2. Fixture matrix

Oracle tools: `pkgutil --check-signature`, `xar -tf`, `xar --dump-toc=<f>` (raw outputs in `oracle/*.txt`). REA results: `rea inspect-signature` / `rea inspect-artifact` from the built worktree CLI.

| Fixture | Construction | Oracle result | REA `inspect_signature` (pre-fix → post-fix) | REA `inspect-artifact` | Match? |
|---|---|---|---|---|---|
| `benign-unsigned.pkg` | `pkgbuild --component Hello.app` | `Status: no signature` | `signed:false` → `capability_unavailable` | inventories Bom/Payload/PackageInfo + gzip-cpio Payload members; all `verified` | correct answer, wrong reason → honest refusal |
| `payload-only.pkg` | `pkgbuild --root payload/` | `Status: no signature` | `signed:false` → `capability_unavailable` | same shape | same |
| `crafted-signed.pkg` | hand-built TOC injection of `<signature style="RSA">` + heap blob, recomputed TOC checksum | `Status: invalid signature` — signature layer **present** | **`signed:false`, "Artifact is not signed."** → `capability_unavailable` | **byte-identical inventory to unsigned pkg**; signature element dropped | **MISMATCH — defect confirmed** |
| `product.pkg` | `productbuild --distribution` (Distribution + nested component pkg) | `Status: no signature` | `signed:false` → `capability_unavailable` | nested `benign-unsigned.pkg/...` members and `Distribution` inventoried as plain files | same |
| `pbzx-payload.pkg` | crafted: Payload heap bytes begin `pbzx`, checksums recomputed | `Status: no signature` | `signed:false` → `capability_unavailable` | Payload occurrence gets limitation `"Payload is a pbzx (LZMA) archive; its members are not expanded. Expand it with pkgutil --expand-full to inspect them."` | correct, but member limitation does not reach top-level coverage (§6) |
| `truncated.pkg` | `head -c 1500` | `package is invalid (checksum did not verify)` | `signed:false` → `capability_unavailable` | clean `artifact_operation_failed`: "xar member has an invalid or out-of-file heap extent" | inventory correct |
| `corrupt-member.pkg` | flipped 1 byte inside Payload heap extent | `package is invalid (checksum did not verify)` | `signed:false` → `capability_unavailable` | `artifact_integrity_mismatch` naming declared vs observed sha1 for `Payload`; with `--integrity-policy record-and-continue` → `hash_status: mismatched` + explicit limitation | correct |
| `corrupt-toc.pkg` | flipped 1 byte inside compressed TOC | `Could not open package` | `signed:false` → `capability_unavailable` | `artifact_operation_failed`: "xar TOC is not zlib data" | inventory correct; sig path previously claimed "unsigned" on an unparseable signature layer |
| `bad-magic.pkg` | first 4 bytes `BAD!` | `Could not open package` | `target_unavailable` (unchanged) | `target_unavailable` | correct — rejected at target resolution before either op |

Pre-fix repro (byte-precise): `codesign -d` on `crafted-signed.pkg` exits 1 with `code object is not signed at all` — identical output to the unsigned fixture — while `pkgutil --check-signature` distinguishes `invalid signature` from `no signature`.

A fully-signed pkg could not be produced: `productsign` requires an Apple-issued installer identity (`security find-identity` found none; a self-signed keychain identity was rejected: "An installer signing identity … is required"). The crafted-signed fixture exercises the same classification code path — REA's output was identical for unsigned and signature-present inputs, and the XarArtifactReader provably ignores `<signature>` TOC elements — so a real signed pkg would be misclassified identically.

## 3. Defect verdict: **CONFIRMED**

`inspect_signature` reported `signed:false` for a pkg whose XAR signature layer existed and was classified `invalid signature` by the oracle — an unverifiable/unevaluated signature layer collapsed into "unsigned". Same mechanism means a *validly* signed pkg would also report `signed:false`.

**Fix applied (this worktree, commit `120c2769a`):** `#inspectSignature` now rejects non-executable/non-Mach-O targets with `AnalysisCapabilityUnavailableError` ("Active artifact is not Mach-O; its container-level signature layer is not evaluated by codesign."), matching the existing `inspect_macho`/`list_architectures` gate. Added boundary test `native signature inspection target scope` in `tests/boundary/providers/native/nativeProvider.test.ts:956-986` covering `pkg` and `elf` targets (asserts `codesign` is never invoked). Verification: `vitest` 78/78 pass across the three native boundary test files; `npm run check:fast` clean; `rea inspect-signature /bin/ls` still returns `signed:true`.

Remaining gap (reported, not fixed): the **inventory** still drops `<signature>` silently — a signed pkg's `inspect-artifact` output is indistinguishable from an unsigned one's. Exposing the signature layer as an observation/limitation would be a feature-sized change (new entry or snapshot limitation plumbing through `XarArtifactReader` → `scanCanonical.buildLimitations`).

## 4. InstallerAlert (`Mac-Installer.InstallerAlert`, sha256 `e12031bc…`)

Universal Mach-O (x86_64 + arm64). Oracles:

- `codesign -dvvv`: signed, `Identifier=Mac-Installer.InstallerAlert`, `TeamIdentifier=58CD8AD5Z4`, authority `Apple Development: Liseth Alejandra Trujillo Garcia (VFYPGAKSLY)` chain to Apple Root CA; both slices signed (`codesign -d -a` exit 0 each).
- `codesign --verify --deep --strict`: **exit 1 — `invalid Info.plist (plist or signature have been modified)`, `In architecture: arm64`** (post-signing tamper of a sealed slot on the arm64 slice).
- `spctl -a -vv`: `notarization indicates this code has been revoked`.

REA (`rea-wt-sig` build): `signed:true`, correct identifier/team/cdhash `5ce14fcc…`/authorities/designated-requirement/entitlements (4 keys: sandbox, network client+server, user-selected read-only), `hardened_runtime:false` (matches flags `0x0`), `code_directory`, `stapled_ticket:not-applicable`, 8 provenance captures including per-slice `codesign -d -a` runs.

**Under-report found in rea-wt-sig (not this branch; reported only):** `verification.status: "unknown"` with limitation "Signature verification is inconclusive … this is not a proven broken signature." The diagnostic `invalid Info.plist (plist or signature have been modified)` is a definitive codesign rejection but is absent from `INVALID_SIGNATURE_REASONS` in `src/native/CodesignVerification.ts:52-66` (`invalidSignatureReason` requires a `startsWith` match, `:68-73`), so `verificationStatus` falls through to `"unknown"` (`:81-97`). The raw diagnostics are preserved, but the status understates a proven-invalid signature. Note the sig worktree has the same pkg defect too: it reported `signed:false` + `verification.status:"unsigned"` for `crafted-signed.pkg`.

## 5. Coverage / unknowns assessment

- **pbzx Payload**: detected by heap head bytes (`XarArtifactReader.ts:677-683`) and recorded with a per-occurrence limitation — honest and correct. However the limitation stays on the occurrence; `coverage.status` still reports `complete-within-substeps` and snapshot/top-level limitations do not aggregate it, so a reader of only the summary would miss it.
- **Distribution / PackageInfo**: inventoried as plain files (hash-verified) with **no semantic parse and no limitation** noting the absence — the pkg's installer scripts, choices, and version metadata are content-invisible without `extract_artifact` + `inspect_plist`.
- **`<signature>` layer**: silently dropped (§1) — no unknown, limitation, or entry. Fixed only at the `inspect_signature` boundary.
- **Missing members**: not modeled. An absent `Bom`/`PackageInfo`/`Payload`/`Distribution` is indistinguishable from a producer that never included one; nothing flags expected-member absence.
- **Corrupted checksums**: the strongest coverage area — strict policy fails with `artifact_integrity_mismatch` naming declared/observed digests and member path; `record-and-continue` retains the member as `mismatched`/untrusted with an explicit aggregated limitation (`scanCanonical.ts:402-425`). TOC checksum, header/member extents, encoding, and truncated streams all produce typed format errors.
- **`next_probes`/`hypotheses`/`unexplored_branches`**: always empty for pkg — no probe is suggested for the pbzx payload or the dropped signature element (the pbzx limitation text suggests `pkgutil --expand-full`, but it is not a structured probe).

## 6. Limitations of this audit

- No real Apple-signed pkg was available (no Developer ID Installer identity); signed-pkg behavior was established via the crafted `<signature>` fixture + code inspection.
- `xar --dump-toc` requires an output filename (`--dump-toc=<file>`); initial `-f`-only invocation printed usage — corrected.
- The InstallerAlert binary was inspected in place and via codesign only; it was never executed.
- The `verification.status:"unknown"` vs oracle `invalid` divergence belongs to the `rea-wt-sig` branch (`CodesignVerification.ts`); no code change was made there.
