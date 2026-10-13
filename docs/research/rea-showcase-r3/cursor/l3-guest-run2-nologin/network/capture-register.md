# Controlled capture register (R3.5 + R3.6)

Raw `.mitm` files are NOT committed. Controlled copies exist in two
locations: guest `~/l3/` (retained for experiment) and host
`/tmp/rea-r32/captures/` (transferred 2026-10-13; SHA-256 verified
against guest-side values byte-identical for every file).

Flow counts below come from `tools/flow-manifest.py` (flows carrying a
parseable `authority` + timestamp). `timestamp_start` markers alone
count slightly more entries (e.g. r0: 63 markers / 27 flows) — the
marker count includes client-error/aborted connection records without
request data. Both counts are reported verbatim; no normalization.

| file | bytes | parsed flows | first ts (UTC) | last ts (UTC) | sha256 |
|---|---:|---:|---|---|---|
| calibration.mitm | 41,661 | 2 | 06:18:41 | 06:19:23 | `1b1bb0efde4f62d3a1941aaa05944dd0a9e9087336aec3307378a3858e0a6259` |
| capture-r0.mitm | 499,879 | 27 | 06:22:16 | 08:14:14 | `4b03d5fbeaaecb9953a4c37ee15519eec8bc7bd4d5e68246a7c59bbd5df6f9cc` |
| capture-r1.mitm | 31,209 | 3 | 08:17:37 | 08:17:39 | `675aacbf4cb33189ec796b61d57462c94c6c77b80bcb84c533ea349511f300be` |
| capture-r2.mitm | 23,807 | 2 | 08:24:15 | 08:24:55 | `90fe7ee3c52b54ed07dd71e7c2cc9946fe6f3c960f4de8d2bf1e708fbeceda5a` |
| capture-u0.mitm | 23,802 | 2 | 09:09:55 | 09:09:57 | `89d8b3f44d8a1fd40009b279db09509aee7431fe345d25e9cfcf6fe7b76af614` |
| capture-u1.mitm | 147,196 | 7 | 09:38:57 | 09:42:18 | `053f30e62b06efcaf69e88256330167ad2207c4e6673f60f0575ad7de712eb2c` |
| capture-u2.mitm | 23,805 | 2 | 09:45:50 | 09:47:38 | `2cdebacffd45f6d1c6cdef14d8f485d2d0dd37af60dbe7d0a3d049875e86b760` |
| capture-u2g.mitm | 28,292 | 3 | 10:02:27 | 10:03:38 | `5672f8af7fa908703cf1b7a74b548d21e56db072730f03c2d36df7b96041c5da` |

Secondary observation files (guest `~/l3/`, not committed — raw lsof
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

Parsability: every `.mitm` was re-opened and scanned on host after
transfer; all parsed without structural errors. This supports "files
survived the guest power event readable"; it does not prove
completeness of any in-flight flow at kill time.

Boundary note for `capture-r0.mitm`: contains flows from BOTH the
aborted first R0 launch (~06:22–06:26) and the later r0b run. The two
`api2.cursor.sh` flows (first 06:22:16) belong to the aborted attempt;
no Cursor flow falls inside r0b's own active window (06:29–06:31).
Suspend/resume gaps (06:31→07:15, 07:15→07:47, 07:47→08:09 UTC) split
the file further — treat as mixed-provenance raw material only.
