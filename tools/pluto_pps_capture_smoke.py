#!/usr/bin/env python3
"""Smoke-test a GPS-gated IQ capture from pluto_ctld (ZMQ :5562)."""

from __future__ import annotations

import argparse
import json
import sys
import time

import zmq


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", default="192.168.1.10", help="SDR IP (eth0 default)")
    ap.add_argument("--port", type=int, default=5562)
    ap.add_argument("--freq", type=int, default=121_500_000)
    ap.add_argument("--rate", type=int, default=3_072_000)
    ap.add_argument("--samples", type=int, default=307_200)  # 0.1 s at 3.072 MS/s
    ap.add_argument("--lead", type=float, default=3.0, help="seconds ahead for t0_gps")
    ap.add_argument("--out", default="/tmp/gp_pps_capture")
    args = ap.parse_args()

    ctx = zmq.Context.instance()
    sock = ctx.socket(zmq.REQ)
    sock.RCVTIMEO = 30_000
    sock.SNDTIMEO = 5_000
    sock.connect(f"tcp://{args.host}:{args.port}")

    sock.send_string("ping")
    ping = json.loads(sock.recv_string())
    print("ping:", json.dumps(ping, indent=2))

    t0 = int(time.time()) + int(args.lead)
    req = {
        "op": "capture",
        "freq_hz": args.freq,
        "sample_rate_hz": args.rate,
        "samples": args.samples,
        "require_gps": True,
        "tdd_sync": True,
        "t0_gps": t0,
        "gain_db": 40,
    }
    print("request:", json.dumps(req))
    sock.send_string(json.dumps(req))

    parts = sock.recv_multipart()
    if len(parts) == 1:
        err = json.loads(parts[0].decode())
        print("CAPTURE FAILED:", json.dumps(err, indent=2))
        return 1

    meta_raw, iq = parts[0], parts[1]
    meta = json.loads(meta_raw.decode())
    meta_path = args.out + ".sigmf-meta"
    iq_path = args.out + ".sigmf-data"
    with open(meta_path, "w", encoding="utf-8") as f:
        json.dump(meta, f, indent=2)
        f.write("\n")
    with open(iq_path, "wb") as f:
        f.write(iq)

    cap0 = (meta.get("captures") or [{}])[0]
    print("iq_bytes:", len(iq))
    print("sample_rate:", (meta.get("global") or {}).get("core:sample_rate"))
    print("gps_ns0:", cap0.get("gpsanchor:gps_ns0"))
    print("method:", cap0.get("gpsanchor:method"))
    print("degraded:", cap0.get("gpsanchor:degraded") or cap0.get("ctl:degraded"))
    print("wrote:", meta_path, iq_path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
