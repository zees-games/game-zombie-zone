#!/usr/bin/env python3
"""Builds sounds/real/*.ogg from the downloaded CC0 packs (see sounds/real/CREDITS.md).

usage: python3 -I tools/build_real_sounds.py <staging dir> [out dir]
Each source is cut (long files at their silences), trimmed, high-passed, brought to TARGET_LUFS
(or a -3 dBFS peak when too short to measure) and written as ogg. Writes real/manifest.json.
"""
import json, os, re, subprocess, sys, tempfile

TARGET_LUFS = -18.0
S = sys.argv[1]
OUT = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "sounds", "real")
os.makedirs(OUT, exist_ok=True)


def run(args):
    return subprocess.run(args, capture_output=True, text=True)


def segments(path, noise="-38dB", gap=0.18, min_len=0.3, max_len=4.0, limit=8):
    r = run(["ffmpeg", "-nostats", "-i", path, "-af", f"silencedetect=noise={noise}:d={gap}", "-f", "null", "-"])
    starts = [float(x) for x in re.findall(r"silence_start: ([\d.]+)", r.stderr)]
    ends = [float(x) for x in re.findall(r"silence_end: ([\d.]+)", r.stderr)]
    dur = float(run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path]).stdout)
    bounds, t = [], 0.0
    for s, e in zip(starts + [dur], [0.0] + ends):
        pass
    cuts = []
    prev_end = 0.0
    for s in starts:
        cuts.append((prev_end, s))
        prev_end = ends[len(cuts) - 1] if len(cuts) - 1 < len(ends) else dur
    cuts.append((prev_end, dur))
    out = [(a, min(b, a + max_len)) for a, b in cuts if b - a >= min_len]
    out.sort(key=lambda x: -(x[1] - x[0]))
    return sorted(out[:limit])


def make(src, name, ss=None, to=None, trim=True, loop=False, gain=0.0):
    dst = os.path.join(OUT, name + ".ogg")
    tmp = tempfile.mkdtemp()
    w = os.path.join(tmp, "a.wav")
    pre = ["ffmpeg", "-y", "-v", "error"]
    if ss is not None:
        pre += ["-ss", str(ss), "-to", str(to)]
    f = "highpass=f=35"
    if trim and not loop:
        f += ",silenceremove=start_periods=1:start_threshold=-48dB,areverse,silenceremove=start_periods=1:start_threshold=-48dB,areverse"
    run(pre + ["-i", src, "-ac", "1", "-ar", "44100", "-af", f, w])
    r = run(["ffmpeg", "-nostats", "-i", w, "-af", "ebur128=peak=true", "-f", "null", "-"])
    m = re.findall(r"I:\s+(-?[\d.]+) LUFS", r.stderr)
    loud = float(m[-1]) if m else -70.0
    if loud > -60:
        g = TARGET_LUFS - loud
    else:
        pk = re.findall(r"Peak:\s+(-?[\d.]+) dBFS", r.stderr)
        g = -3.0 - float(pk[-1]) if pk else 0.0
    g = max(-20.0, min(24.0, g)) + gain
    fade = "" if loop else ",afade=t=in:d=0.004,areverse,afade=t=in:d=0.02,areverse"
    res = run(["ffmpeg", "-y", "-v", "error", "-i", w, "-af", f"volume={g}dB,alimiter=limit=0.89:level=disabled{fade}",
               "-c:a", "libvorbis", "-q:a", "4", dst])
    dur = float(run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", dst]).stdout or 0)
    if res.returncode != 0 or dur < 0.08:
        print("FAILED/empty", name, src, res.stderr[:200])
        if os.path.exists(dst):
            os.remove(dst)
        return None
    return name


def P(*a):
    return os.path.join(S, *a)


manifest = {}  # event -> list of {file, source, id}


def add(event, items):
    manifest.setdefault(event, [])
    for it in items:
        n = len(manifest[event]) + 1
        name = f"{event}_{n}"
        src, kw, label = it
        if make(src, name, **kw):
            manifest[event].append({"file": name, "source": label})


def whole(path, label, **kw):
    return (path, kw, label)


def cut(path, label, **kw):
    return [(path, {"ss": a, "to": b}, label) for a, b in segments(path, **kw)]


AD = lambda n: whole(P("artisticdude-zombies/zombies", f"zombie-{n}.wav"), "artisticdude")
AP = lambda n: whole(P("arcadeparty-voice/Voice Effects Zombie-Skeleton-Monster Human Male", n + ".wav"), "arcadeparty")
OG = lambda n: whole(P("ogrebane-monster/monster_sfx_pack", f"monster-{n}.wav"), "ogrebane")
SN = lambda n: whole(P("starninjas-growls", f"monster.{n}.ogg"), "starninjas")
R1 = lambda n: whole(P("rubberduck-80-1", n + ".ogg"), "rubberduck-1")
R2 = lambda n: whole(P("rubberduck-80-2", n + ".ogg"), "rubberduck-2")
FS = lambda i, who: whole(P("freesound", f"{i}.mp3"), who)
KD = lambda n: whole(P("kenney-digital", n + ".mp3"), "kenney-digital")

add("moan", cut(P("darsycho-moans/darsycho__zombie-moans_0.ogg"), "darsycho", min_len=0.6)
    + [AD(n) for n in (16, 17, 18, 19, 20, 21)]
    + [whole(P("saturn91-zomby", f), "saturn91") for f in ("01_zombey.mp3", "02_zombey.mp3", "03_zombey.mp3", "04_zombey_0.mp3")]
    + [FS(754438, "ownathan")])
add("rage", [AP(f"zombieYell{n}") for n in (1, 2, 3, 4, 5, 6, 7, 8, 9, 10)] + [R1("scream_01"), R1("scream_02"), FS(144003, "arrigd")])
add("claw", [R2("attack_02"), R2("attack_03"), R1("grunt_01"), R1("grunt_02"), R1("grunt_03"), OG(1), OG(2), OG(3)])
add("die", [AP(f"zombieDeath{n}") for n in (1, 2, 3, 4)] + [R2("die_01"), R2("die_02"), FS(534602, "jollygreenz")])
add("hurt", cut(P("vinrax-pain/zombie_pain.flac"), "vinrax", min_len=0.25) + [R1(f"hurt_0{n}") for n in range(1, 6)])
add("leaper", [SN(n) for n in (1, 2, 3, 4, 5)])
add("strangler", [R1("cough_01"), R1("cough_02"), R1("cough_03"), OG(4), OG(5)])
add("bloater", [R1("burble_01"), R1("burble_02"), R1("burp_01"), R1("burp_02")])
add("ram", [SN(n) for n in (6, 7, 8, 9, 10)])
add("spitter", [R1("spit_01"), R1("spit_02"), R1("spit_03"), R2("slime_01"), R2("slime_02"), R2("slime_03"), R2("slime_04")])
add("rider", [SN(n) for n in (11, 12, 13, 14, 15, 16)])
add("brute", cut(P("trazzz-roar/monster_roar.wav"), "trazzz123", min_len=0.8, gap=0.25, max_len=5.0, limit=4) + [R1("roar_01"), R1("roar_02"), R1("roar_03")])
add("screamer", [R1("scream_01"), R1("scream_02"), FS(144003, "arrigd"), OG(8)])
add("crawler", [R1("eat_01"), R1("eat_02"), R1("eat_03"), R1("eat_04"), R1("breath")])
add("riot", [R1("troll_01"), R1("troll_02"), R1("troll_03"), R1("grunt_04"), R1("grunt_05")])
add("mutant", [R1("monster_01"), R1("monster_02"), R1("monster_03"), R1("monster_04"), OG(6), OG(7), OG(9), OG(10)])
add("mutant_zap", [KD("zap1"), KD("zap2"), KD("zapTwoTone"), KD("zapThreeToneDown")])
add("mutant_grab", [KD("phaserUp1"), KD("phaserUp2"), KD("powerUp8"), KD("phaseJump3")])
add("mutant_throw", [KD("phaserDown1"), KD("phaserDown2"), whole(P("ezduzziteh-boost/boost_0.mp3"), "ezduzziteh")])
add("gore_bone", [whole(P("zanelittle-bones", f"Deep Break {n}.wav"), "zanelittle") for n in range(1, 11)])
add("gore_rip", cut(P("eldritch-meat/rippingintomeat_0.mp3"), "eldritch-grim", min_len=0.5, gap=0.2, max_len=3.0, limit=6))
add("gore_splat", [(f, {"ss": a, "to": b}, "independent.nu")
                   for f in [P("independent-splatter-x/extreme_splatter/crack11.mp3.flac"), P("independent-splatter-x/extreme_splatter/crack12.mp3.flac")]
                   for a, b in segments(f, min_len=0.3, max_len=2.5, limit=4)])
# Beds and loops: not trimmed to silence, not faded.
for ev, items, ln in (("horde", [(P("freesound/616999.mp3"), "perrybassin", 0.0, 10.0), (P("freesound/111044.mp3"), "garyq", 5.0, 25.0),
                                 (P("freesound/111044.mp3"), "garyq", 40.0, 60.0), (P("freesound/111044.mp3"), "garyq", 80.0, 100.0)], True),):
    manifest.setdefault(ev, [])
    for i, (src, who, a, b) in enumerate(items):
        name = f"{ev}_{i + 1}"
        if make(src, name, ss=a, to=b, loop=True, gain=-2.0):
            manifest[ev].append({"file": name, "source": who})
manifest.setdefault("mutant_jet", [])
for i, (num, who) in enumerate(((402816, "jacksonacademyashmore"), (733986, "velcronator"), (512815, "mostyxs"))):
    name = f"mutant_jet_{i + 1}"
    if make(P("freesound", f"{num}.mp3"), name, loop=True):
        manifest["mutant_jet"].append({"file": name, "source": who})

json.dump(manifest, open(os.path.join(OUT, "manifest.json"), "w"), indent=1)
for k, v in manifest.items():
    print(k, len(v))
