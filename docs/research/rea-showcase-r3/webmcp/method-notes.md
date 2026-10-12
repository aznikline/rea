# WebMCP method notes

## Retraction: dual-channel flag-vs-token measurement is not novel

An earlier draft of this work claimed that "nobody does dual-channel
flag-vs-token measurement" of WebMCP deployment. **That claim is retracted.**

The Mudpie WebMCP directory (https://mudpie.ai/webmcp/) and its Lazyweb
mirror (https://www.thelazyweb.com/webmcp/) already publish a measurement of
this exact shape:

- 6,934 production candidate sites, each loaded in Chrome 152 **twice**: once
  "as a normal visitor" and once "with the trial forced on" — i.e. a default
  channel and a flag-forced channel, which is the same two-mode discrimination
  this pilot uses (default vs `--enable-features=WebMCPTesting`).
- Their published classes are a superset of the discrimination vocabulary we
  proposed: `live` (registered under stock Chrome), `code-unenrolled`
  (registration code present, no origin-trial token detected), `live-polyfill`
  (a JS shim registers tools invisible to Chrome's own agent), `bridge-primed`
  (edge agent bridge installed, WebMCP pack off), `token-idle` (valid token,
  no tools observed), `none`.
- They already state the same epistemic boundary: "a registration shows that
  a page exposed a tool; it does not establish that an agent used it"
  (see also https://mudpie.ai/blog/registration-is-not-execution/), and they
  count the platform-wide Shopify Liquid token rollout separately from
  individually inspected sites.

So the flag-vs-token two-channel method, the registration≠execution caveat,
and the polyfill distinction are all prior art, publicly documented as of
September 2026 (their snapshot dates), before this work.

## What remains as REA's actual differentiation

After the retraction, REA's contribution is narrower and must be stated
without novelty claims:

1. **Passive attach with a strictly weaker authority.** REA uses only
   `WebMCP.enable` plus `toolsAdded`/`toolsRemoved` events on an existing CDP
   endpoint and target. It never sends `WebMCP.invokeTool`, never sends
   `Runtime.evaluate`, and never navigates or reloads the page. Whether the
   published crawlers' loaders evaluate page code beyond registration is not
   stated in their method; REA's bound is explicit and verifiable in the wire
   command log.
2. **Per-frame identity.** Each observed registration carries `frame_id`,
   `frame_url`, and `owner_origin`, with same-name registrations in distinct
   frames kept as separate owners and out-of-scope frames excluded with
   counted reasons. Directory crawls record site-level state.
3. **Evidence provenance.** Results are hash-bound Evidence records that
   round-trip through `export_evidence_bundle` / `inspect-evidence-bundle`
   unchanged, including the declared `consequential` annotation hint after
   the `fix/webmcp-annotations` correction (previously dropped during
   normalization even though the CDP `Annotation` type carries it).
4. **Explicit unobservable classes in the evidence itself.** Unavailable
   domain, out-of-scope frames, malformed protocol values, and dropped events
   land in the result's completeness ledger (`unavailable_sections`,
   `excluded` with reasons, `dropped_events`) rather than only in a prose
   method note. Classes like `token-idle`/`code-unenrolled` are shared with
   prior work; the machine-readable accounting is the delta.

## Scope cautions carried forward

- `debugging` is a fifth optional `Annotation` boolean in the protocol on
  current Chromium main (WebMCP `debugging` hint, documented from Chrome 156
  for the JS-side annotation). Chrome 154 cannot emit it; it is not yet
  surfaced by REA. Flagged as a remaining gap, not silently absent.
- A registration observation under the testing flag demonstrates the page's
  code path works when the API is exposed; it does not demonstrate the site
  is enrolled in the origin trial or that deployed users can reach it.
- Conversely, a default-mode miss does not prove absence of code; token
  checks require inspecting the delivered document for `origin-trial`
  headers/meta, which REA's passive capture does not decode.
