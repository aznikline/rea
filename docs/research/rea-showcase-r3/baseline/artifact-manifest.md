# Artifact manifest

Hash-source classes (do not conflate):

- **local-computed**: SHA-256 computed on this host over the preserved file.
- **cask-record**: SHA-256 recorded in the Homebrew cask definition for the
  corresponding vendor download URL. Community-maintained record of a vendor
  artifact; it is *not* a vendor-published signature. Agreement between
  local-computed and cask-record is corroboration, not vendor attestation.
- **vendor-feed**: version/commit metadata returned by the vendor's own
  download/update endpoints.
- **community-published**: hash/metadata published by a third party
  (Objective-See, SentinelOne, forum posts). Treated as claims until
  locally verified.

## Cursor artifacts (`/Users/wizout/op/targets/cursor/`)

| Artifact | SHA-256 (local-computed) | Version/commit (vendor-feed) | Hash corroboration |
|---|---|---|---|
| `Cursor-3.14.7-darwin-arm64.zip` | `393dc55f28c13992989ad62f73bb57e46b3600eb33886c15801f5864231ae958` | 3.14.7 / `a758f2241ca99fecf380180b6cbdbbce0f1f42cf` | matches cask-record |
| `Cursor-3.20.21-darwin-arm64.zip` | `be54b6add6d30bcd40235be1f5a9d9bc65e0977ca2e55bee8fe011af73048c49` | 3.20.21 / `f09fca384ceca23f7bf21f9c23655b162641d747` | matches cask-record |
| `Cursor-3.23.23-darwin-arm64.zip` | `0e58594d5fb53bc6c413b36690e94e79f7fd487f8302224152321298990473f8` | 3.23.23 / `2dac2428994fe34f12658d9ecad1541b98db2c04` | matches cask-record |
| `Cursor-3.24.9-darwin-arm64.zip` | `30e9ece5856afaae63472aa66f19d83e4ac0d179b9db93649b5083cd8fd276cd` | 3.24.9 / `cd6d2a1f2e56e9841f0ed9c7c24542087b4e69be` | matches cask-record |
| `Cursor-3.24.12-darwin-arm64.dmg` | `c5ed7193bfb906e2aae3f3f281c62cb979efd1b662c73524a15f1c4448734f5f` | 3.24.12 / `37b865941ccb31e2fc90c685157534efca87f964` | no independent hash record located; local-computed only |
| `forum-174299.json` | `c0ca5900e87c1f123b1c0fd958a76d54c8a0955ce728b9fda7097440e3da5c3a` | n/a | community-published source (forum API capture) |
| `policy-{terms-of-service,data-use,privacy,security,subprocessors}.html` | see `SHA256SUMS.txt` | n/a | vendor-published pages, captured 2026-10-12 |

Extracted app trees (not committed): `cursor-3.14.7/` and `cursor-3.20.21/`
contain only the extracted `workbench/` JS; `cursor-3.23.23/`,
`cursor-3.24.9/`, `cursor-3.24.12/` contain full `Cursor.app` trees.

Static marker counts in `workbench.desktop.main.js` were identical across
**all five versions** (3.14.7 → 3.24.12): `externalCliAnalytics`×3,
`ex_hs2`×2, `ex_hs`×4, `enable_ex_hs`×2, `history.jsonl`×2,
`external-cli-analytics-poll`×1. Earliest observed = 3.14.7 (July build);
first-introduction version remains UNKNOWN (L1 only; identical marker counts
do not establish identical behavior).

**Download-URL caveat (recorded):** under
`downloads.cursor.com/production/<commit>/darwin/arm64/`, the versioned
filename `Cursor-3.20.21-darwin-arm64.zip` returns a 263-byte error body;
the working artifact name is non-versioned `Cursor-darwin-arm64.zip`. Its
SHA-256 matches the cask-record.

Oracle outputs for the pkg task are committed in-repo under
`docs/research/rea-showcase-r3/pkg/oracle/`:
`pkgutil-check-signature.txt`, `xar-tf.txt`, `xar-dump-toc.txt`,
`malformed-oracle.txt`, `crafted-product-oracle.txt`,
`InstallerAlert-oracle.txt`. Fixture `.pkg` binaries are not committed
(regeneration commands in `pkg/correctness-report.md`).

## versus-pkg related samples (`/Users/wizout/op/targets/versus-pkg/`)

| Artifact | SHA-256 (local-computed) | Provenance |
|---|---|---|
| `Ferret.zip` | `6eaea2d30c9e8790b597a05a35c3f59f3bab669d3b596b763ff2e4f442910562` | Objective-See-related distribution (community-published) |
| `FlexibleFerret.zip` | `2f210054cdd4612d8c9240b54410b1ec5555db291b88897e9b02b192ac71e27e` | same |
| `extracted/Ferret/FlexibleFerret/Mac-Installer.InstallerAlert` | `e12031bc7ac1fa70cb802a508a8c520bb5431f0e5f303a7097e3e6c8fd3d147a` | universal Mach-O extracted from `Ferret.zip` |
| `extracted/Ferret/FriendlyFerret/com.apple.secd` | `65b98ddc821212d13e0e64265353725f0adf6bcf3f4129c18d9d6327b8a69e11` | universal Mach-O extracted from `Ferret.zip` |
| `extracted/Ferret/FrostyFerret/growth` | `bd2aa5805b76f272b43a595b3d73e29d0fc4647e15e87950b8f904ea26dcf053` | extracted member |
| `extracted/Ferret/FrostyFerret/CameraAccess.zip` | `76d54945e80c205fb3436116e357a584ca098d7a2d9368c9f1a51319f63190fb` | extracted member |

### Correction (recorded)

Earlier notes recorded `versus.pkg` "SHA-256
`388ac48764927fa353328104d5a32ad825af51ce`". That string is 40 hex
characters — consistent with SHA-1, not SHA-256. It is a
**community-published** value with ambiguous algorithm labeling; it must not
be cited as a verified SHA-256. The `versus.pkg` container itself has **not
been obtained**; container end-to-end analysis remains NOT_RUN. Extracted
members above are not a substitute for the container.

`Mac-Installer.InstallerAlert` codesign metadata (observed locally, exit
non-zero on verify — signature metadata readable, validity not asserted):
Authority `Apple Development: Liseth Alejandra Trujillo Garcia (VFYPGAKSLY)`,
TeamIdentifier `58CD8AD5Z4`. Revocation/notarization status: **unknown**
(REA does not check revocation; requires separate evidence).
