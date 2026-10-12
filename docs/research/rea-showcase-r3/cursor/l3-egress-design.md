# L3 content-egress — execution design (VM-authorized R3.2)

Status: EXECUTION AUTHORIZED for the VM path below, per R3.2 review. The
"dedicated host user" option is explicitly NOT authorized. No host keychain/
trust, proxy, pf, or VPN state may be modified; the host's role is limited
to running `tart` and mounting a read-only artifacts directory into the VM.

## Goal

Determine whether `ex_hs2` event bytes (and which fields) leave the client —
the only question R3-CUR-RUN-1 left open.

## Environment

- Hypervisor: `tart` 2.40.1 (cirruslabs, Developer ID signed, sha256 of
  tarball verified against release checksums — see
  `evidence/tart-provenance.txt` once produced).
- Guest: `ghcr.io/cirruslabs/macos-sequoia-vanilla:latest` (recorded by
  digest after pull). Vanilla = no accounts, no toolchains.
- Host mounts into guest via `tart run --dir` (read-only where supported):
  - `cursor/` artifact directory (dmg/zip, hash-verified earlier)
  - `tools/` (run-experiment.sh, extract-evidence.sh, verify-evidence.sh)
- Synthetic data only; no personal Cursor/Claude/Codex/Apple account login.
- mitmproxy + its temporary CA live INSIDE the guest only; `pf` UDP-443
  block (if needed to defeat QUIC fallback) is guest-scoped, recorded as
  an intervention, and reverted before the VM is destroyed.
- Host VPN/fake-IP: the guest's default route is measured and recorded
  (`route get` + destination IP check); if host VPN still NATs guest egress,
  that is recorded as a coverage limitation, not silently assumed away.

## Run matrix (fixed, R3.2)

| Run | Inputs | Purpose |
|---|---|---|
| R0 | `--history none` | baseline startup traffic |
| R1 | `--history canary`, unique run-scoped canary | local-read → event → egress chain |
| R2 | fresh run dir, new canary, same as R1 | reproducibility check |

All runs use `run-experiment.sh` inside the guest. `--disable-crash-reporter`
is recorded in the manifest as an intervention (matching R3 RUN-1); if a
baseline-without-it comparison is needed it is a separate labeled run.

## Semantics discipline

- `proxy-delivered` ≠ `upstream-sent` ≠ `response-observed` — reported as
  three separate fields per flow.
- A MITM capture proving only local delivery is NOT egress evidence.
- Connect-RPC/protobuf: raw bytes kept (`binary_fields`), `protoc
  --decode_raw` first; third-party `.proto` = unverified mapping.
- Certificate pinning, QUIC-only egress, or handshake failure are recorded
  as coverage results, not negative egress results.
- Raw breadcrumb records (with duplicates) and deduplicated views are kept
  separate; duplicates never counted as multiple sends.

## Cleanup

1. `extract-evidence.sh --run <guest run dir> --out <fresh dir>` — sanitized
   excerpts only; full captures and CA keys stay out of the repo.
2. Delete guest mitmproxy CA + private key, remove guest pf rule.
3. `tart delete rea-l3-vm`; record host-unchanged check (trust settings,
   `scutil --proxy`, pf state snapshots taken before/after).
