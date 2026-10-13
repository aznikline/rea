import json, re, datetime, collections, os
SRC = "/tmp/rea-r32/captures/decoded"
DST = "/Users/wizout/op/rea-wt-research/docs/research/rea-showcase-r3/cursor/l3-guest-run2-nologin/network"
TARGET = re.compile(r"cursor\.(sh|com|dev)$|cursor-cdn|statsig|sentry")
for fn in sorted(os.listdir(SRC)):
    d = json.load(open(os.path.join(SRC, fn)))
    cap = fn.replace(".json", "") + ".mitm" if not fn.endswith("mitm") else fn
    recs = d["records"]
    tgt, other = [], collections.Counter()
    for r in recs:
        h = r.get("host") or ""
        if TARGET.search(h) or (fn.startswith("calibration") and h == "example.com"):
            tgt.append({
                "ts_utc": datetime.datetime.fromtimestamp(r["ts_start"], datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ") if r.get("ts_start") else None,
                "method": r.get("method"), "host": h,
                "path": r.get("path"),
                "status": (r.get("response") or {}).get("status"),
                "error": r.get("error"),
                "req_body_state": (r.get("req_body") or {}).get("state"),
                "req_body_raw_len": (r.get("req_body") or {}).get("raw_len"),
                "req_body_dec_len": (r.get("req_body") or {}).get("dec_len"),
            })
        else:
            other[h or "?"] += 1
    out = {
        "source_capture": cap,
        "decoder": "mitmproxy 12.2.3 FlowReader via mitmdump -nr + addon hooks",
        "records_total": len(recs),
        "type_counts": d.get("type_counts"),
        "decode_errors": d.get("errors", []),
        "target_flows": tgt,
        "non_target_hosts_counts_only": dict(other.most_common()),
        "note": "decoded with official mitmproxy API; non-target system flows reduced to host+count"
    }
    with open(os.path.join(DST, "decoded-" + fn.replace(".json","").replace("capture-","") + ".json"), "w") as f:
        json.dump(out, f, indent=1)
    print(fn, len(recs), "target:", len(tgt))
