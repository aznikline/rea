# Canary / marker search receipt

Search object: **raw container bytes** of each `.mitm` (the file
contains mitmproxy's serialized flow records; decrypted request/response
payloads are embedded for intercepted HTTPS flows). This is a
container-byte search — stronger than decoded-only for these captures
because intercepted content is stored plaintext. Non-decryptable or
body-elided flows would not be covered; no `flow_detail` truncation was
observed in the stored streams.

Patterns searched (verbatim bytes): each run's full run-id,
`canary-claude`, `canary-codex`, `REA_R33_CANARY` prefix, `ex_hs2`,
`api3.cursor.sh`, `/tev1/` (statsig log-event proxy path from
product.json), `sessionId`, `agent`.

## Results

| capture | run id | canary-claude | canary-codex | REA_R33_CANARY | ex_hs2 | api3 | /tev1/ |
|---|---:|---:|---:|---:|---:|---:|---:|
| capture-r1.mitm | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| capture-r2.mitm | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| capture-u0.mitm | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| capture-u1.mitm | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| capture-u2.mitm | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| capture-u2g.mitm | 0 | 0 | 0 | 0 | 0 | 0 | 0 |

`agent` matched u2 twice — both hits are `user-agent:` header strings
inside weatherkit/stocks flows, not analytics content.

Interpretation bound: zero hits = "these decrypted, proxy-captured
bytes did not contain the markers". It does not exclude event content
sent un-decrypted, over a path not covered, or events that were never
enqueued because a gate upstream failed.
