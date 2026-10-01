#!/usr/bin/env python3

import argparse
import asyncio
import json
import os
import random
import statistics
import sys
import time

import httpx

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from kommandeur_format import STANDARD_QUESTIONS, build_request
from proben import PROBES


def pct(xs, p):
    xs = sorted(xs)
    return xs[min(len(xs) - 1, int(round(p / 100 * (len(xs) - 1))))]


async def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default="http://127.0.0.1:8765")
    ap.add_argument("--rate", type=float, default=20.0, help="Anfragen je Sekunde")
    ap.add_argument("--seconds", type=float, default=60.0)
    ap.add_argument("--timeout", type=float, default=10.0)
    ap.add_argument("--format", choices=["text", "json"], default="text")
    ap.add_argument("--json-out", default="")
    args = ap.parse_args()

    bodies = [json.dumps(build_request(s, STANDARD_QUESTIONS, args.format)) for _, s, _ in PROBES]
    lat, server_ms, batch_req, errors = [], [], [], []
    rss = []
    limits = httpx.Limits(max_connections=200, max_keepalive_connections=200)
    async with httpx.AsyncClient(timeout=args.timeout, limits=limits) as client:
        h = (await client.get(args.url + "/health")).json()
        rss.append(h["rss_mb"])

        await client.post(args.url + "/decide", content=bodies[0], headers={"Content-Type": "application/json"})

        async def one(body):
            t0 = time.perf_counter()
            try:
                r = await client.post(args.url + "/decide", content=body,
                                      headers={"Content-Type": "application/json"})
                dt = (time.perf_counter() - t0) * 1000
                if r.status_code != 200:
                    errors.append("http_%d" % r.status_code)
                    return
                d = r.json()
                lat.append(dt)
                server_ms.append(d["latency_ms"])
                batch_req.append(d["timing"]["batch_requests"])
            except Exception as e:
                errors.append(type(e).__name__)

        async def sample_rss(stop):
            while not stop.is_set():
                try:
                    rss.append((await client.get(args.url + "/health")).json()["rss_mb"])
                except Exception:
                    pass
                await asyncio.sleep(1.0)

        stop = asyncio.Event()
        sampler = asyncio.create_task(sample_rss(stop))
        n = int(args.rate * args.seconds)
        start = time.perf_counter()
        tasks = []
        for i in range(n):
            due = start + i / args.rate
            delay = due - time.perf_counter()
            if delay > 0:
                await asyncio.sleep(delay)
            tasks.append(asyncio.create_task(one(random.choice(bodies))))
        await asyncio.gather(*tasks)
        wall = time.perf_counter() - start
        stop.set()
        await sampler
        h = (await client.get(args.url + "/health")).json()

    res = {
        "rate_target": args.rate, "seconds": args.seconds, "sent": n, "ok": len(lat), "errors": len(errors),
        "error_kinds": sorted(set(errors)), "throughput_rps": round(len(lat) / wall, 2),
        "p50_ms": round(pct(lat, 50), 1) if lat else None, "p95_ms": round(pct(lat, 95), 1) if lat else None,
        "p99_ms": round(pct(lat, 99), 1) if lat else None, "max_ms": round(max(lat), 1) if lat else None,
        "share_under_1s": round(sum(x < 1000 for x in lat) / n, 3),
        "mean_batch_requests": round(statistics.mean(batch_req), 2) if batch_req else None,
        "rss_mb_start": rss[0], "rss_mb_max_sampled": max(rss), "peak_rss_mb": h.get("peak_rss_mb"), "load_s": h.get("load_s"), "server_stats": h.get("stats"),
        "format": args.format,
    }
    print(json.dumps(res, indent=1))
    if args.json_out:
        with open(args.json_out, "w") as f:
            json.dump(res, f, indent=1)


if __name__ == "__main__":
    asyncio.run(main())
