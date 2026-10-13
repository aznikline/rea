"""mitmdump addon: decode every flow in a .mitm capture to a metadata manifest.
Run: DUMP_OUT=out.json mitmdump -nr CAPTURE.mitm -s decode-dump.py
Emits metadata only — no bodies, headers, cookies, or auth material.
"""
import json, os
from mitmproxy import ctx, http, tcp, udp, dns, websocket

CANARIES = [b"REA_R33_CANARY", b"canary-claude", b"canary-codex",
            b"ex_hs2", b"api3.cursor.sh", b"/tev1/", b"sessionId"]

_by_id = {}
errors = []

def _body_state(msg):
    if msg is None:
        return ("absent", None, None, [])
    try:
        raw = msg.raw_content
    except Exception as e:
        return ("raw_error", None, None, [f"raw:{type(e).__name__}"])
    if raw is None:
        return ("none", None, None, [])
    raw_state = "empty" if raw == b"" else "present"
    hits = [c.decode() for c in CANARIES if c in raw]
    try:
        dec = msg.content
        if dec is None:
            return (raw_state, len(raw), None, hits)
        for c in CANARIES:
            if c in dec and c.decode() not in hits:
                hits.append("decoded:" + c.decode())
        return (raw_state, len(raw), len(dec), hits)
    except Exception as e:
        return (raw_state, len(raw), f"decode_error:{type(e).__name__}", hits)

def _http(f):
    req = _body_state(f.request)
    rec = _by_id.get(f.id) or {
        "id": f.id, "type": "http",
        "method": f.request.method, "host": f.request.host,
        "path": f.request.path[:200],
        "ts_start": f.request.timestamp_start,
        "client_peer": str(f.client_conn.peername) if f.client_conn.peername else None,
    }
    rec["req_body"] = {"state": req[0], "raw_len": req[1], "dec_len": req[2], "hits": req[3]}
    if f.response:
        r = _body_state(f.response)
        rec["response"] = {"status": f.response.status_code,
                           "ts": f.response.timestamp_end or f.response.timestamp_start,
                           "body": {"state": r[0], "raw_len": r[1], "dec_len": r[2], "hits": r[3]}}
    if f.error:
        rec["error"] = str(f.error)[:160]
    _by_id[f.id] = rec

def request(f):  _http(f)
def response(f): _http(f)
def error(f):    _http(f) if isinstance(f, http.HTTPFlow) else _generic(f)

def _generic(f, t=None):
    rec = _by_id.get(f.id) or {"id": getattr(f, "id", None)}
    rec["type"] = t or getattr(f, "type", "?")
    rec["messages"] = len(getattr(f, "messages", []) or [])
    _by_id[f.id] = rec

def tcp_message(f):       _generic(f, "tcp")
def udp_message(f):       _generic(f, "udp")
def websocket_message(f): _generic(f, "websocket")
def dns_request(f):       _generic(f, "dns")
def dns_response(f):      _generic(f, "dns")

def done():
    recs = sorted(_by_id.values(), key=lambda r: (r.get("ts_start") or 0))
    types = {}
    for r in recs:
        types[r.get("type","?")] = types.get(r.get("type","?"),0)+1
    ctx.log.info(f"decode-dump: {len(recs)} records, types={types}, errors={len(errors)}")
    out = os.environ.get("DUMP_OUT")
    if out:
        with open(out, "w") as fh:
            json.dump({"records": recs, "errors": errors, "type_counts": types}, fh, indent=1)
