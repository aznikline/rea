import json, collections, re
TARGET = re.compile(r"cursor\.(sh|com|dev)$|cursor-cdn|statsig|sentry")
for c in ["calibration","r0","r1","r2","u0","u1","u2"]:
    f = "/Users/admin/l3/manifests/flows-%s.json" % c
    d = json.load(open(f))
    target = [fl for fl in d["flows"] if TARGET.search(fl["host"] or "")]
    other = collections.Counter(fl["host"] for fl in d["flows"] if not TARGET.search(fl["host"] or ""))
    if c == "calibration":
        target += [fl for fl in d["flows"] if fl["host"] == "example.com"]
    out = {
        "source_capture": d["file"],
        "flow_count_total": d["flow_count"],
        "target_flows": target,
        "non_target_hosts_counts_only": dict(other.most_common()),
        "note": "non-target flows are system noise; host names and counts only"
    }
    open(f,"w").write(json.dumps(out, indent=1))
    print(c, "total:", d["flow_count"], "target:", len(target))
