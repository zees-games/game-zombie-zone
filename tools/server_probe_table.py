#!/usr/bin/env python3
"""Turns the RESULT lines of tools/server_probe.sh logs into markdown tables: python3 tools/server_probe_table.py .godot/probe-logs/*.log"""
import json, sys, os
rows = []
for path in sys.argv[1:]:
    for line in open(path):
        if line.startswith("RESULT "):
            r = json.loads(line[7:]); r["tag"] = os.path.basename(path); rows.append(r)
rows.sort(key=lambda r: (r["tag"].count("_c"), r["rate"] * -1, r["n"]))
P = ["bots", "players", "logic", "senses", "brains", "bodies", "horde_other", "net_pull", "net_history", "net_snapshot", "total"]
print("| survivors | Hz | commons | budget ms | total mean / p50 / p95 / max | " + " | ".join(p for p in P[:-1]) + " (mean) | engine step | B/s/peer | MB peak |")
print("|" + "---|" * (9 + len(P) - 1 + 1))
for r in rows:
    ph = r["phases"]; t = ph["total"]
    fixed = "fixed" if "_c" in r["tag"] else "cap"
    print("| %d | %d | %d (%s %d) | %.1f | %.1f / %.1f / %.1f / %.1f | %s | %.2f | %d | %d |" % (
        r["n"], r["rate"], r["commons"], fixed, r["commons_cap"], r["budget_ms"], t["mean"], t["p50"], t["p95"], t["max"],
        " | ".join("%.2f" % ph.get(p, {"mean": 0})["mean"] for p in P[:-1]), r["engine_step_ms"]["mean"], r["bytes_per_s_per_peer"], r["rss_peak_mb"]))
print()
print("| survivors | Hz | paths/tick | us/search | pathing ms (derived, inside brains) |")
print("|---|---|---|---|---|")
for r in rows:
    print("| %d | %d | %.2f | %.0f | %.2f |" % (r["n"], r["rate"], r["searches_per_tick"], r["us_per_search"], r["path_ms_derived"]))
