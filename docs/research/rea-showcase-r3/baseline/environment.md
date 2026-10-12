# Baseline — environment and repository identity

Captured: 2026-10-12 (local time, host macOS).

## Git state

- Repository: `morluto/rea` (upstream, read-only for actor `aznikline`)
- Fork: `aznikline/rea` — `viewerPermission: ADMIN`, `isFork: true`
- Local remotes at capture:
  - `origin` = `https://github.com/morluto/rea.git` (read-only for this account)
  - `fork`   = `ssh://git@ssh.github.com:443/aznikline/rea.git`
- BASE_SHA (origin/main at baseline fetch):
  `974f11d010570c0a18423cd1cc93e9a5203df1b6`
  (`docs: clarify responsible use and preserve third-party notices (#2082)`)
- Research branch: `research/showcase-r3` (worktree `/Users/wizout/op/rea-wt-research`), based on BASE_SHA.

## Worktrees at capture (all preserved as WIP; none reset)

| Path | Branch | HEAD | Purpose |
|---|---|---|---|
| `/Users/wizout/op/rea` | `integration/high-value` | `1502a9b0198bd043535364595bf08d04ad9f445c` | merged compatibility-first + intrinsic-boundaries; `git status` clean |
| `/Users/wizout/op/rea-wt-pkg` | `integration/feat/pkg-inventory` | `702dfb351` | XAR/cpio `.pkg` inventory merge (tested) |
| `/Users/wizout/op/rea-wt-sig` | `integration/feat/signature-posture` | `c3450b1bf` | signature posture merge (tested) |
| `/Users/wizout/op/rea-wt-dyld` | `integration/feat/dyld-shared-cache` | `4b34bc001` | dyld shared cache merge (tested; includes post-merge fixups) |
| `/Users/wizout/op/rea-wt-research` | `research/showcase-r3` | this document | evidence/program records |

Stashes: none. Upstream push: not authorized for `morluto/rea` (403 for
`aznikline`); pushes go to `fork` only. Remote branch deletion script
`/Users/wizout/op/delete-dead-branches.sh` exists, unexecuted.

Worktrees added after baseline capture:

| Path | Branch | HEAD | Purpose |
|---|---|---|---|
| `/Users/wizout/op/rea-wt-webmcp` | `fix/webmcp-annotations` | `354ec7cee` | consequential fix + doc corrections → draft PR morluto/rea#2263 |
| `/Users/wizout/op/rea-wt-siggate` | `fix/inspect-signature-non-macho` | `028054116` | signature gate fix off `origin/main` `d96550f2f` → draft PR morluto/rea#2262 |

## Installed/executing REA

REA runs from source checkouts (no installed release build):

- `package.json`: `rea-agents` version `6.4.0`
- `bin`: `scripts/rea.mjs` (entry: `rea`, `rea-agents`)
- No `dist/` build present at capture; execution is source + tsx/vitest
  toolchain. Toolchain pinned by `.nvmrc` and `packageManager` field.
- ACTUAL_REA_BUILD_ID: not applicable (no packaged build). Proxy identity:
  `rea-agents@6.4.0` source tree at the HEAD SHA listed per worktree above.
  Any report citing REA behavior must name the worktree + HEAD used, since
  `.pkg` inventory capability exists only in `rea-wt-pkg`.

## Host toolchain

- macOS 27.0.1 (arm64 host)
- Node v26.0.0, npm 11.12.1, git 2.51.2
- Google Chrome 154.0.8037.98 (`/Applications/Google Chrome.app`)
- `node_modules` present in all four analysis worktrees
- `gh` authenticated as `aznikline`

## Evidence directories (outside repo; not committed)

- `/Users/wizout/op/targets/cursor/` — preserved Cursor artifacts
- `/Users/wizout/op/targets/versus-pkg/` — related samples (no `versus.pkg`
  container obtained; see `baseline/artifact-manifest.md`)
