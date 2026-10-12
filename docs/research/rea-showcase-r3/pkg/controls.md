# Real signed-pkg control — python.org

Requested by R3.1 review: a validly-signed pkg does not require owning the
signer's identity — verify an existing one.

## Artifact

- `python-3.13.9-macos11.pkg` (69.8 MB) from
  `https://www.python.org/ftp/python/3.13.9/python-3.13.9-macos11.pkg`
- SHA-256 (local-computed): `dafebf62b8737f341f6b7eca2d6d1153a50a6b1bfbfa4b8aaf0e62adc73e5017`
- Vendor-published authenticity evidence: detached PGP signature
  `python-3.13.9-macos11.pkg.asc` fetched alongside (not verified against a
  pinned key — recorded as provided-by-vendor material, not as verified).
- Held locally at `/tmp/rea-r3-pkg/controls/`; not committed (binary).

## Oracle (`pkgutil --check-signature`)

```
Status: signed by a developer certificate issued by Apple for distribution
Notarization: trusted by the Apple notary service
Signed with a trusted timestamp on: 2025-10-14 14:45:21 +0000
Certificate Chain:
  1. Developer ID Installer: Python Software Foundation (BMM5U3QVKW)
  2. Developer ID Certification Authority
```

## REA result (post-gate, `fix/inspect-signature-non-macho`)

`rea inspect-signature python-3.13.9-macos11.pkg` →
`capability_unavailable`, reason "Active artifact is not Mach-O; its
container-level signature layer is not evaluated by codesign."

Interpretation: a genuinely-signed pkg previously produced `signed:false` /
"Artifact is not signed."; it now produces an honest "this provider does not
evaluate that layer" refusal. The xar `<signature>` layer itself still gets
no observation (known gap, tracked).

## Supported-target regression

`rea inspect-signature /bin/ls` → `signed: true`, identifier
`com.apple.ls`, designated requirement intact — gate does not misreject
Mach-O targets.
