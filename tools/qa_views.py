#!/usr/bin/env python3
"""Print `map view at look` lines: spawn (the way the survivors face), far (toward the farthest nav floor or spawn), spawner (a trader or zombie spawn)."""
import json, math, sys, glob, os
root = os.path.join(os.path.dirname(__file__), "..", "maps")
for p in sorted(glob.glob(root + "/*.json")):
    d = json.load(open(p))
    if not d.get("world"): continue
    i = d["id"]
    sp0 = d["spawns"]["survivors"][0]
    s = sp0["at"]
    # The survivors' real facing (forward is -sin, -cos of the yaw), from 1.2 m behind the first seat and above the
    # heads: the seat itself is occupied by the camera's own body, and the next seat is 0.6 m ahead (its hair filled the view).
    a = math.radians(sp0.get("yaw", 0.0))
    fx, fz = -math.sin(a), -math.cos(a)
    eye = (s[0] - fx * 1.2, s[1] + 2.2, s[2] - fz * 1.2)
    pts = [((f[0]+f[2])/2, f[4], (f[1]+f[3])/2) for f in d["nav"]["floors"]]
    pts += [tuple(z) for z in d.get("zombie_spawns", [])]
    far = max(pts, key=lambda q: (q[0]-s[0])**2 + (q[2]-s[2])**2)
    def f(v): return ",".join("%.2f" % x for x in v)
    print(i, "spawn", f(eye), f((eye[0] + fx * 12, eye[1] - 0.8, eye[2] + fz * 12)))
    print(i, "far", f(eye), f((far[0], eye[1]-0.5, far[2])))
    zs = d.get("zombie_spawns") or [far]
    z = zs[len(zs)//2]
    print(i, "spawner", f((z[0], z[1]+1.7, z[2])), f((s[0], s[1]+1, s[2])))
