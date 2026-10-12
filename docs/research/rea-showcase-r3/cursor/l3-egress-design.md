# L3 content-egress — preparation design (no trust changes made)

Status: DESIGN ONLY. Nothing here has been executed; no certificate trust,
pf, global proxy, or VPN state was or will be modified without separate
explicit authorization.

## Goal

Determine whether `ex_hs2` event bytes (and what fields) leave the client —
the only question R3-CUR-RUN-1 left open.

## Constraints (binding)

- Dedicated test account or a revertible macOS test environment only — the
  daily account's keychain/trust, proxy, pf, and VPN are out of scope.
- Temporary CA exists only inside the experiment environment and is removed
  with it; record cleanup and rollback steps before starting.
- Synthetic data only (canary histories + isolated HOME, as in RUN-1).
- No external disclosure emails without separate authorization.

## Design options (evaluated)

| Option | Trust impact | Field visibility | Notes |
|---|---|---|---|
| A. Dedicated macOS test user + mitmproxy (`--mode local` per-process) + user-login-keychain CA | test user only | full | preferred — isolation is OS-level, rollback = delete user |
| B. Disposable VM (Tart/UTM) + mitmproxy + VM-only CA | none on host | full | heavier setup; cleanest boundary |
| C. `SSLKEYLOGFILE` + own CA-free proxy | none | TLS app data via keylog | works only if Electron honors the env var — verify first (often doesn't for bundled network stacks) |
| D. Plain HAR of Chromium network service via `--log-net-log` | none | netlog records hostnames + payload metadata, not decrypted bodies | useful complement, not a substitute |

## Semantics discipline (from review)

- "Client delivered bytes to the local proxy" ≠ "proxy forwarded to vendor."
  Both legs must be observed; a MITM capture that only proves local delivery
  is labeled `proxy-delivered`, not `egressed`.
- Connect-RPC/protobuf bodies: record raw bytes first (`binary_fields`),
  decode with `protoc --decode_raw`; third-party `.proto` files are
  unverified mappings only.
- Two run profiles, separately labeled: DEFAULT (fresh profile) and
  INTERVENTION (explicitly documented flag/setting changes). Intervention
  results never describe default behavior.

## Blockers recorded

- Cursor may pin certificates or use QUIC — a forced-TCP/failed-handshake
  outcome is itself a result, labeled accordingly.
- VPN fake-IP NAT on the host masks destination IPs — the test environment
  must not inherit the daily-account VPN.
