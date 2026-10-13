# Independent connection-metadata cross-check (R3.6)

Two observation channels besides the mitmproxy flow list, both applied
identically to U0/U1/U2/U2g:

1. **lsof sampler** — `lsof -nP -i -c Cursor` every 5 s during the run
   (selection quirk: `-i` and `-c` are OR'd in lsof, so logs also
   contain non-network FD rows of matching processes; only TCP/UDP
   socket rows are analyzed here).
2. **NetLog** — `--log-net-log` diagnostic switch passed to the target
   for all conditions. Limitation: Chromium writes the netlog file
   incrementally but the runner terminates the target with SIGKILL, so
   each netlog-*.json is truncated at the last flush (≈ launch phase).
   It therefore corroborates early-window behavior only.

## Per-run Cursor socket summary (lsof, 5 s cadence)

| run | Cursor TCP sockets to remote | UDP sockets | notes |
|---|---|---|---|
| u0 | 0 direct; 1× `127.0.0.1:*→127.0.0.1:8888` (proxy) persistent | 0 | all external TCP went via proxy |
| u1 | 0 direct; 1× `→127.0.0.1:8888` persistent | 0 | same |
| u2 | 0 direct; 1× `→127.0.0.1:8888` persistent | 0 | same |
| u2g | none in filtered rows (see limits) | 0 | GUI-session run |

`198.18.x.x:443` connections observed in samples belong to mitmdump's
own upstream forwarding legs (vz-NAT synthesized DNS range), not to any
Cursor process — verified by process name column.

## NetLog destination summary (truncated files)

| run | hostnames present | endpoints |
|---|---|---|
| u0 | api2.cursor.sh only | 127.0.0.1:8888, 127.0.0.1:443, loopback |
| u1 | api2.cursor.sh only | 127.0.0.1:8888, 192.168.64.1:53 (DNS) |
| u2 | api2.cursor.sh only | 127.0.0.1:8888, 192.168.64.1:53 |
| u2g | api2.cursor.sh only | 127.0.0.1:8888, 192.168.64.1:53 |

u2g's netlog mentions api2.cursor.sh but no api2 flow exists in its
`.mitm` — a connection attempt toward the proxy that produced no
completed flow (run ended or CONNECT left idle).

## Coverage verdict (this method, these runs)

- All Cursor-owned TCP sockets sampled across U0–U2g terminate at the
  loopback proxy or loopback IPC; **zero direct egress and zero UDP**
  sockets were observed in any sample. QUIC/UDP bypass is therefore not
  merely unproven-by-proxy but additionally unobserved in OS socket
  metadata for these runs — bounded by 5 s sampling granularity
  (sub-5 s connections could evade sampling; NetLog truncation leaves
  the post-launch window partially un-instrumented).
- The proxy-visible decrypted flow sets match: only
  `api2.cursor.sh /extensions-control` (u0/u1/u2) or nothing (u2g).
- `launch.log` update-URL absence explained: `AgentHostUpdater` logged
  "watching ... idle until an extension host writes hosts/<pid>.json"
  and `update#setState idle` — the URL was constructed, never fetched
  (agentHostEnabled=false in renderer.log). The api2 updateURL line is
  likewise URL construction, not a request. No bypass inferred.

## Not covered

- Flows shorter than the 5 s lsof cadence.
- Traffic by non-`Cursor`-named helpers (e.g. `CursorUIViewService` is
  an Apple XPC text-input service, unrelated).
- Server-side processing of anything — unreachable from this vantage.
