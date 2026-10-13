# L3 Guest Run 1 — R0/R1/R2 first round

Scope: first interpretable observation round in the dedicated guest VM.
Separately labeled **macOS 15.7.7 arm64 guest** — not merged with any
host-side run statistics.

## Environment identity

| Item | Value |
|---|---|
| Guest | `rea-l3-vm` (tart), macOS 15.7.7 arm64, admin (uid 501) |
| VM image digest | `ghcr.io/cirruslabs/macos-sequoia-vanilla@sha256:57a83b1b52f928f5b11b0963927178fd6c4cac52c315279f227c27cc5ab81587` |
| Target Mach-O SHA-256 | `71e8dfc19ff2216a277315972dcca0ea83773e8ec214f3cf352ee9591ce38037` (match) |
| Workbench JS SHA-256 | `044ce0931100af5fe95403e9a692b02932bc3e13a6763f576b851f503fefa518` (match) |
| Proxy | mitmproxy 12.2.3, `127.0.0.1:8888`, guest `Ethernet` service HTTP+HTTPS system proxy |
| CA trust | guest-local `~/.mitmproxy` CA, user-domain trust via admin login keychain; required ONE interactive GUI authorization (no headless path found — see below) |
| Program baseline | `research/showcase-r3` `02a7204535d2af60648ffc02b03a8364faeac8b2` |

## Capture calibration

`GET https://example.com/` via `127.0.0.1:8888` → 200. The `.mitm` capture
contains the full decrypted flow: request line/headers, HTTP/2 response
`200` with complete HTML body, TLS metadata on both client and server
connections (sni, ALPN, cipher, certificate list). Confirms
proxy-delivered + upstream-sent + response-observed, with body saved.
Upstream TLS verification kept on; `ssl_insecure` not used; target binary
unmodified.

## Results matrix

| Run | Inputs | INTEGRITY | VALIDITY | OBSERVATION | ELIGIBLE |
|---|---|---|---|---|---|
| R0 `r0b-1791872989-1024` | real empty history | PASS | VALID | NOT_OBSERVED_WITHIN_WINDOW | YES |
| R1 `r1-1791879453-1237` | 2 synthetic canaries | PASS | VALID | NOT_OBSERVED_WITHIN_WINDOW | YES |
| R2 `r2-1791879851-1416` | fresh canary, clean state | PASS | VALID | NOT_OBSERVED_WITHIN_WINDOW | YES |

Manifest excerpts: R1 ready at launch+5.06s, observed window 235.1s;
identity `match`, workbench `match`, remaining processes 0 for all runs.

## L3 destination observations (per-run mitmproxy captures)

| Run | Cursor-bound flows | Other flows (guest system noise) |
|---|---|---|
| capture-r0.mitm (500KB, spans aborted r0 + r0b) | 2× `GET api2.cursor.sh/extensions-control` (200, 16B) | stocks-data-service, weatherkit, ocsp2.apple.com |
| capture-r1.mitm (31KB) | 1× `GET api2.cursor.sh/extensions-control` (200, 16B); launch.log also references `api2.cursor.sh/updates/api/update/...` (not in capture — see limits) | weatherkit, configuration.ls.apple.com |
| capture-r2.mitm (24KB) | 1× `GET api2.cursor.sh/extensions-control` (200, 16B) | weatherkit |

Canary byte search over decrypted captures (`REA_R33_CANARY`,
`canary-(claude|codex)`, run IDs): **0 matches** in r1, r2, and r0
captures.

## What was actually observed — and what was not

Positive bounded facts:

- Cursor 3.24.12 launched inside the guest, reached the defined
  readiness state (`window*_wb*/renderer.log` non-empty +
  `state.vscdb` present) in ~5s, ran the full observation window,
  terminated cleanly with zero remaining processes.
- Cursor's network activity visible to the proxy is minimal: only
  `GET api2.cursor.sh/extensions-control`. `telemetry.log` and
  `network-shared.log` exist but were empty; `state.vscdb` is a single
  4KB page.
- No `cursor-sentry-events.log` was created in ANY run — the `ex_hs2`
  breadcrumb mechanism did not activate at all in this environment
  (`files_scanned=0, missing_dir=true` in extract-report).
- `grep -rl 'canary' home/cursor-data/` finds nothing: the planted
  history content was not referenced anywhere under the app's data dir.
- No canary content appears in decrypted HTTP(S) flows.

This is a legitimate negative *within stated coverage*. It does NOT
exclude:

- QUIC/HTTP3 (UDP 443) or direct connections that bypass the HTTP(S)
  system proxy entirely — no `--disable-quic` intervention was applied.
- Mechanisms requiring a logged-in account, an opened project folder,
  or agent-panel use — none were exercised (`login=none`).
- ex_hs2 firing under different conditions; its complete absence here
  means the stream itself never started, so its absence proves nothing
  about its contents when active.

## Operational incidents recorded

- `r0-aborted-ssh-kill`: first R0 attempt died when the controlling SSH
  session's expect wrapper timed out and tore down the remote runner —
  no manifest (trap killed mid-write). Preserved as a failure record;
  runner subsequently detached via guest-side `nohup`.
- The guest powered off after R2 completed (host-side window close
  suspected). All R2 evidence (manifest, capture) was already flushed;
  nothing lost.
- CA trust required exactly one interactive GUI authorization;
  documented attempts (authdb rules, Admin.plist, session injection,
  direct API, LaunchAgent, profiles, RFB) all failed — macOS 15.7.7
  enforces interactive consent for trust settings in this posture.

## Corrections (R3.6 review follow-up)

**R0 window is NOT a ~240s observation.** Its manifest records
`total_runtime_s=6015.9`, `observed_window_s=6010.8`. Decoded flow
timestamps in `capture-r0.mitm` show gaps at 06:31→07:15→07:47→08:09
UTC. Guest suspend/resume is a *candidate* explanation (kernel-time
`sleep` freezes while wall-clock advances), but no lifecycle record
proves it — so "active ≈240 s" is also unconfirmed. R0 is excluded
from equal-window comparison purely on unexplainable-window grounds.

**capture-r0.mitm attribution (formal decode, mitmproxy 12.2.3).**
28 HTTP records. `api2.cursor.sh/extensions-control` appears twice:
06:22:20 (aborted first R0) and 06:29:55 (inside r0b's launch window —
r0b *did* emit one captured Cursor request). Three records carry
`peer closed connection` errors; none are silently omitted.

**Mechanism framing corrected.** `files_scanned=0, missing_dir=true`
proves only that the `cursor-sentry-events.log` source does not exist
in these runs. "Workbench reached readiness", "specified log absent",
and "target mechanism executed" are three separate judgements — this
round establishes the first two only.

**Coverage scope.** `ELIGIBLE=YES` applies to the *declared
methodology* (manifest + packaged inputs + scoped extraction); it does
not extend to "all outbound network paths verified negative". QUIC /
direct connections bypassing the system HTTP(S) proxy remain
uncovered. The `launch.log`-referenced update URL absent from the
capture is an open question, not evidence of bypass.

## Artifact locations

- Guest: `/Users/admin/l3/{runs,evidence-r*,capture-*.mitm}`
- This repo: `l3-guest-run1/evidence-{r0,r1,r2}/` (manifests, hashes,
  inputs, extract reports), `l3-guest-run1/runs/` (run-manifest.json per
  run). Raw `.mitm` captures are retained on the guest only — they may
  contain system traffic; not committed.
