# Canary / marker search receipt — formal-decode revision

Supersedes the earlier container-byte receipt. Correction: "container
bytes are a stronger search" is **withdrawn**. TLS interception does
not imply HTTP content-encoding is removed, and `raw_content` may
still be compressed; `msg.content` (decoded) and `msg.raw_content`
must be searched separately. `flow_detail` only controls display
verbosity — it says nothing about whether bodies were stored, so no
body-completeness claim rests on it.

Decoder: mitmproxy 12.2.3 (`mitmdump -nr`, `tools/decode-dump.py`).
For every decoded flow the addon records `none | empty | present |
raw_error | decode_error` per request/response body — absent, empty,
and undecodable are counted separately.

Patterns: run-id, `canary-claude`, `canary-codex`, `REA_R33_CANARY`,
`ex_hs2`, `api3.cursor.sh`, `/tev1/`, `sessionId`, `agent`.

## Three-layer results (all captures)

| capture | records | container-byte hits | raw-body hits | decoded-body hits |
|---|---:|---:|---:|---:|
| calibration | 5 | 0 | 0 | 0 |
| capture-r0 | 28 | 0 | 0 | 0 |
| capture-r1 | 3 | 0 | 0 | 0 |
| capture-r2 | 2 | 0 | 0 | 0 |
| capture-u0 | 2 | 0 | 0 | 0 |
| capture-u1 | 7 | 0 | 0 | 0 |
| capture-u2 | 2 | 0 | 0 | 0 |
| capture-u2g | 3 | 0 | 0 | 0 |

Body states across all HTTP records: every request body except
u2g's `POST fbs.smoot.apple.com` (present, Apple feedback payload)
and one calibration POST is `empty`; responses `present` except r1's
one `empty` response and u2g's two `empty`. No `decode_error`s, no
`raw_error`s — nothing was un-decodable.

`agent` hits in u2's container bytes were `user-agent:` header
strings — verified benign, unchanged.

Interpretation bound (still applies): zero hits at all three layers =
"the successfully decoded request/response content of these captured
flows contains none of the markers". It still cannot exclude traffic
outside the proxy path, events never enqueued, or server-side use.
