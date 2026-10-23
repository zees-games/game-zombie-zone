#!/usr/bin/env python3
"""Print `map view at look` lines: spawn, far (toward the farthest nav floor or spawn), spawner (a trader or zombie spawn)."""
import json, math, sys, glob, os
root = os.path.join(os.path.dirname(__file__), "..", "maps")
for p in sorted(glob.glob(root + "/*.json")):
    d = json.load(open(p))
    if not d.get("world"): continue
    i = d["id"]
    s = d["spawns"]["survivors"][0]["at"]
    eye = (s[0], s[1] + 1.6, s[2])
    pts = [((f[0]+f[2])/2, f[4], (f[1]+f[3])/2) for f in d["nav"]["floors"]]
    pts += [tuple(z) for z in d.get("zombie_spawns", [])]
    far = max(pts, key=lambda q: (q[0]-s[0])**2 + (q[2]-s[2])**2)
    near = min(pts, key=lambda q: (q[0]-s[0])**2 + (q[2]-s[2])**2 if (q[0]-s[0])**2 + (q[2]-s[2])**2 > 100 else 1e9)
    def f(v): return ",".join("%.2f" % x for x in v)
    # spawn view: look at nearest point >10 m away
    print(i, "spawn", f(eye), f((near[0], eye[1]-0.3, near[2])))
    print(i, "far", f(eye), f((far[0], eye[1]-0.5, far[2])))
    zs = d.get("zombie_spawns") or [far]
    z = zs[len(zs)//2]
    print(i, "spawner", f((z[0], z[1]+1.7, z[2])), f((s[0], s[1]+1, s[2])))
