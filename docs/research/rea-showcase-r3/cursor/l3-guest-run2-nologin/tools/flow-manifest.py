#!/usr/bin/env python3
# sanitized flow manifest: method, host, path, status, timing only.
# No headers, cookies, bodies, or query payloads beyond path.
import re, sys, datetime, json
fn = sys.argv[1]
data = open(fn, "rb").read()
flows = re.split(rb"(?=timestamp_created)", data)
out = []
for fl in flows:
    tc = re.search(rb"timestamp_created;17:(\d+\.\d+)", fl)
    ts = re.search(rb"timestamp_start;17:(\d+\.\d+)", fl)
    hs = re.search(rb"authority;\d+:([a-zA-Z0-9.\-]+)", fl)
    meth = re.search(rb"method;\d+:([A-Z]+)", fl)
    path = re.search(rb"scheme;\d+:https,]?\d*:\d+:(?:path);\d+:([^,\]]+)", fl)
    path2 = re.search(rb"path;\d+:([^,\]]{1,200})", fl)
    code = re.search(rb"status_code;3:(\d{3})", fl)
    if hs and (ts or tc):
        t = float((ts or tc).group(1))
        out.append({
            "ts_utc": datetime.datetime.fromtimestamp(t, datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "method": meth.group(1).decode() if meth else None,
            "host": hs.group(1).decode(),
            "path": (path or path2).group(1).decode(errors="replace")[:160] if (path or path2) else None,
            "status": int(code.group(1)) if code else None,
        })
out.sort(key=lambda f: f["ts_utc"])
print(json.dumps({"file": fn.split("/")[-1], "flow_count": len(out), "flows": out}, indent=1))
