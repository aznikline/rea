# WebMCP passive pilot — 5 sites, 2026-10-12

Goal: validate the measurement method, not census scale. Passive only; no
tool invocation, no page evaluation, no navigation by REA.

## Fixed configuration

- Chrome 154.0.8037.98 (`/Applications/Google Chrome.app`), dedicated profile
  `/tmp/rea-r3-chrome-profile` (deleted after each run; removed entirely at
  the end). **User's normal Chrome untouched.**
- Remote debugging on `http://127.0.0.1:19222`. **Deviation from plan:**
  port 9222 was already bound on 127.0.0.1 by the user's normal Chrome
  (PID 1963, LISTEN). A dedicated loopback port was substituted rather than
  attach to or disturb that browser. All other config as specified.
- Fresh launch per mode; one tab per site; ~60 s window per site
  (≈45 s settle after `Target` creation, then
  `rea discover-webmcp-tools --observation-ms 10000`; observed windows
  55–57 s).
- Two Chrome modes per site: default, and `--enable-features=WebMCPTesting`.
- Measurement path: **REA-level** — built REA at `fix/webmcp-annotations`
  (final commit `449c58a37`; pilot ran against code-identical `b587c25fa`,
  later commits differ only in docs and message text) via
  `node scripts/rea.mjs discover-webmcp-tools`. REA sends only
  `WebMCP.enable` and consumes `toolsAdded`/`toolsRemoved`; `WebMCP.invokeTool`
  and `Runtime.evaluate` are never sent (verified in fixture command logs and
  by provider design).
- Frame scope: recorded per run via `Page.getFrameTree` on the page target
  (PROTOCOL-LEVEL helper, frame inventory only — no tool data taken from it).
- Static channel: delivered HTML/headers checked for `origin-trial`
  meta/header and WebMCP code markers; tokens decoded to their JSON payload
  (`feature`, `origin`, `isSubdomain`, `isThirdParty`).

## Site selection

| Class | Site | Justification |
|---|---|---|
| known-positive (origin trial) | zapier.com | Mudpie directory `live` class, 7 tools captured 2026-09; recognizable production site |
| code-present / flag-only candidate | gillette.de | Mudpie `code-unenrolled`, 4 tools |
| known-negative | example.com | trivially no WebMCP code |
| polyfill-only | feverup.com | Mudpie `live-polyfill`, 4 tools; HTML loads `webmcp-polyfill`/`mcp-b` |
| iframe-complex / SPA | cnn.com (→ edition.cnn.com) | large page with many transient subframes |

## Results

| Site | default tools | flag tools | token | code markers | classification |
|---|---|---|---|---|---|
| zapier.com | 5 | 5 | WebMCP, first-party `isSubdomain` (script-injected meta, `data-webmcp-origin-trial`) | registerTool (native) | **deployed-token** |
| gillette.de → www.gillette.de/de-de | 0 | 4 | WebMCP token present but `isThirdParty: true` | registerTool present | **code-present** (served token is third-party-scoped; did not activate the API for this document) |
| example.com | 0 | 0 | none | none | **negative** |
| feverup.com → /en | 0 | 0 | none | `webmcp-polyfill`, `mcp-b`, `modelContext` | **polyfill** |
| cnn.com → edition.cnn.com | 0 | 0 | none | none | **negative** for tools; frame-complexity observation below |

`status: "available"` in every run, both modes: the `WebMCP` CDP domain itself
is **not** flag-gated in Chrome 154 — the flag/token gates page-side API
exposure, not the debug domain.

### Observed tools

- zapier.com (both modes): `list_top_searched_apps`, `list_popular_apps`,
  `list_app_categories`, `list_app_guides`, `list_trending_apps` — all
  imperative, main frame, `owner_origin: https://zapier.com`.
  Annotations per tool: `read_only: true`, `untrusted_content: false`,
  **`consequential: false`** (declared), `autosubmit: null` (absent).
- gillette.de (flag only): `searchtool`, `viewReviews`, `viewProduct`,
  `viewArticle` — all imperative, main frame. `viewReviews` declares
  `untrusted_content: true`, `consequential: false`; others
  `untrusted_content: false`, `consequential: false`.

### Frame scope (protocol-level inventory)

- cnn.com: 8 frames; 1 main (`edition.cnn.com`) + 7 subframes at
  `about:blank`/`about:srcdoc`. REA excluded all 7 with
  `reason: unsupported_url` (counted in `completeness.excluded`). No WebMCP
  tools in any frame.
- zapier.com: 2 excluded subframes (`unsupported_url`).
- feverup.com: 2 excluded subframes (`unsupported_url`).
- gillette.de, example.com: single frame.

## Newly observed classification nuance

Mudpie's vocabulary (`live` / `code-unenrolled` / `token-idle` /
`live-polyfill` / `bridge-primed` / `none`) does not cover the gillette.de
case: a **served token that is `isThirdParty`-scoped** and therefore does not
activate the feature for the first-party document. Token presence is not
token applicability; passive HTML inspection alone cannot distinguish this —
the two-channel (default vs flag) observation can. gillette.de registers 4
tools only under the flag. (Note: Mudpie's 2026-09-03 snapshot labeled it
`code-unenrolled`; a third-party-scoped token has been added since — or was
not detected — which is itself a time-drift observation.)

## Unobservable / limitation classes recorded

- **Polyfill registrations are invisible to the native CDP domain in both
  modes.** feverup's shim registers into its own JS registry; Chrome's
  `WebMCP.toolsAdded` never sees them even under `WebMCPTesting`. Detection
  requires static/script evidence (which we used) — i.e. `status:
  "available"` + 0 tools does not exclude a deployed polyfill.
- **`unsupported_url` subframes** (about:blank/srcdoc placeholders) are
  excluded with counts — REA records them explicitly rather than silently.
- **Redirects**: gillette.de → www.gillette.de and cnn.com → edition.cnn.com
  move the target origin mid-load; discovery scopes to the settled origin.
  (An explicit `--allowed-origins` computed from the request URL produced
  `target_not_allowed` — a scope-authoring pitfall, now avoided by defaulting
  to the settled target origin.)
- **Registration timing**: the fixed 45 s settle + 10 s window catches
  registrations present at attach plus late replays. Tools registered only on
  interaction (e.g. after scrolling/consent) are unobservable by this method.
- **`debugging` annotation** (protocol on Chromium main, Chrome ≥156): cannot
  be emitted by Chrome 154; not yet surfaced by REA.

## Round-trip verification

- Real Evidence record `ev_e451abd530…` (zapier, default mode) was wrapped in
  a minimal bundle, re-read by `rea inspect-evidence-bundle` (summary and
  `detail: complete`), and re-encoded by `rea evidence-export`
  (6,382 bytes canonical). `annotations.consequential` survived every hop
  (`false` declared on zapier tools — value not collapsed).
- Domain-level test `src/domain/webMcpDiscovery.test.ts` covers
  true/false/null declared values, historical captures missing the key
  (`undefined`), and `createEvidenceBundle` → `serializeEvidenceBundle` →
  `parseEvidenceBundle` preservation.

## Remaining gaps

- Single run per site per mode; no retry/interaction coverage.
- Protocol-level `toolsAdded` was not recorded raw for the pilot (REA-level
  only); a raw-CDP cross-check would confirm REA normalization drops nothing
  else (e.g. future `debugging` hints).
- Origin-trial token semantics (`isThirdParty` vs first-party activation)
  inferred from token payload + observed behavior, not from Chrome internals.
- Shopify `live` candidate (allbirds/gymshark) was pre-empted: curl probes hit
  storefront bot defenses and no token was visible in static HTML — zapier
  substituted from the same verified `live` index class.
- `webmcp.com` verified index was not used; the Mudpie directory (6,934-site
  snapshot embedded in-page) provided per-class candidates instead.
