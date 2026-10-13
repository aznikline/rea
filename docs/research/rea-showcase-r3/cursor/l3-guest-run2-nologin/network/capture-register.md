# Controlled capture register (R3.5 + R3.6), formal-decode revision

Raw `.mitm` files are NOT committed. Controlled copies: guest `~/l3/`
(RETAINED_FOR_EXPERIMENT) and host `/tmp/rea-r32/captures/` —
SHA-256 verified identical on both sides at transfer time.

**Flow counts and timings below are produced by mitmproxy 12.2.3's
official decoder** (`mitmdump -nr <capture> -s tools/decode-dump.py`,
same version that wrote the captures). An earlier regex-based manifest
(`tools/flow-manifest.py`, splitting on `timestamp_created` markers)
is superseded and retained in `tools/` only as historical record; its
undercounts (e.g. calibration 2→5, r0 27→28) show why it is not a
record-boundary authority. Zero `FlowReadException`s were raised in
any file.

| file | bytes | decoded HTTP flows | first req ts (UTC) | last req ts (UTC) | sha256 |
|---|---:|---:|---|---|---|
| calibration.mitm | 41,661 | 5 | 06:18:40 | 06:20:25 | `1b1bb0efde4f62d3a1941aaa05944dd0a9e9087336aec3307378a3858e0a6259` |
| capture-r0.mitm | 499,879 | 28 | 06:22:17 | 08:14:14 | `4b03d5fbeaaecb9953a4c37ee15519eec8bc7bd4d5e68246a7c59bbd5df6f9cc` |
| capture-r1.mitm | 31,209 | 3 | 08:17:37 | 08:17:39 | `675aacbf4cb33189ec796b61d57462c94c6c77b80bcb84c533ea349511f300be` |
| capture-r2.mitm | 23,807 | 2 | 08:24:15 | 08:24:55 | `90fe7ee3c52b54ed07dd71e7c2cc9946fe6f3c960f4de8d2bf1e708fbeceda5a` |
| capture-u0.mitm | 23,802 | 2 | 09:09:55 | 09:09:57 | `89d8b3f44d8a1fd40009b279db09509aee7431fe345d25e9cfcf6fe7b76af614` |
| capture-u1.mitm | 147,196 | 7 | 09:38:57 | 09:42:18 | `053f30e62b06efcaf69e88256330167ad2207c4e6673f60f0575ad7de712eb2c` |
| capture-u2.mitm | 23,805 | 2 | 09:45:50 | 09:47:38 | `2cdebacffd45f6d1c6cdef14d8f485d2d0dd37af60dbe7d0a3d049875e86b760` |
| capture-u2g.mitm | 28,292 | 3 | 10:02:27 | 10:03:38 | `5672f8af7fa908703cf1b7a74b548d21e56db072730f03c2d36df7b96041c5da` |

All decoded records are type `http`. No WebSocket/TCP/UDP/DNS flow
records exist in any capture. Three r0 flows end with
`peer closed connection` errors (stocks-data-service at 07:47:15) —
recorded as error records, not silently dropped.

Secondary observation files (guest-only, not committed — raw lsof
output contains unrelated system file paths):

| file | sha256 |
|---|---|
| conns-u0.log | `dcbfc098c8803d62d8da044da12320e6b8bf813bae3f20a26f3df53cad8bf706` |
| conns-u1.log | `8f5079626c7920d5ceb1eb4d10c618228e73b30c567f0f5f68ce0cd6fb73c768` |
| conns-u2.log | `96d21ec95be94d961bcb188526a69ba1367bdfc8783b11cc1157f8a4d6003421` |
| conns-u2g.log | `0c196606cd6a30f90270c5918034b09d3a5c93924bbf8e20c70f66cc90ac9cc3` |
| netlog-u0.json (truncated) | `f12b445ec23cc2d450d7338e84b65877ef2d420e75c0c0fb317e6b8f78b0ec80` |
| netlog-u1.json (truncated) | `ab4fa24e17c29f8d8247141edfd3b16da28090a6d20da7cd8ceab8e761e1331f` |
| netlog-u2.json (truncated) | `2905d5f8d29fcf68d719b556ccc07f773d3ab438caedb96b554ebd4e4b34f4c4` |
| netlog-u2g.json (truncated) | `06bf7497ddf5ea44b0319fc360bdb6363b86c0b7f6d00f266b7be8c53ef3ddf6` |

## R0 provenance (decoded)

Two `GET api2.cursor.sh/extensions-control` (200) exist in
capture-r0.mitm: 06:22:20 (aborted first R0 launch) and **06:29:55 —
inside r0b's own launch window** (r0b launch epoch ≈ 06:29:52). The
earlier statement that r0b produced no Cursor flow is corrected: r0b
did emit exactly one captured Cursor request.

Flow gaps 06:31→07:15, 07:15→07:47, 07:47→08:09 UTC remain explained
only as *candidate* guest suspend/resume: no Tart lifecycle log
establishing suspend has been produced, so r0b's manifest wall-clock
(6010.8 s) stays excluded from equal-window comparison and its active
duration is NOT confirmed to be ≈240 s.
