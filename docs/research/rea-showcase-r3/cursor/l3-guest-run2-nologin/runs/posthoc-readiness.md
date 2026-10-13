# Post-hoc readiness re-adjudication (U1/U2/U2g)

Original manifests are unchanged. This note re-judges "ready" from raw
logs; both records coexist deliberately.

The harness detector required a `window*_wb*/` log directory. Folder
windows log under `window1/` (no `_wb` suffix — the suffix marks the
empty-workbench window variant), so U1/U2/U2g flagged
`workbench_readiness_not_reached` while actually loading the
workbench.

Renderer-log comparison (u0 vs u1, verbatim on guest):

- u0 (`window1_wb0/renderer.log`, 83 lines) opens with
  `[CursorExtensionIsolationService] Extension isolation is disabled
  (forced disabled in glass mode)` and ends with
  `[AgentHostService] using legacy implementation`.
- u1 (`window1/renderer.log`, 83 lines) opens with the identical
  service-init sequence — first line differs only in saying isolation
  is `enabled` (non-glass workbench mode) — and ends at the same
  `[AgentHostService]` line.
- `state.vscdb` exists in all runs (post-create, ~4 KiB fresh DB).

Post-hoc judgement: the workbench did initialize in U1/U2/U2g to the
same observable depth as U0. The `ready=0` flag records a detector
mismatch on logdir naming, not a target failure. This note does not
promote them to `ELIGIBLE` retroactively — the flag limitation is
recorded instead of rewritten.

Detector fix needed for any future round: match `window*/renderer.log`
regardless of `_wb` suffix.
