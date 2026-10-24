#!/usr/bin/env python3
"""Builds sounds/ambience/ from the CC0 candidates (SOURCES.tsv beside them).

    tools/make_ambience_set.py ~/godot/_ambient_candidates

    tools/make_ambience_set.py ~/godot/_ambient_candidates --out /tmp/amb   # to look first (tools/audit_ambience.py --dir)

Beds: stereo, loudness-matched to BED_LUFS, trimmed to MAX_BED seconds, made seamless by
crossfading the end into the start. One-shots: mono (they are placed in the world), peak-limited,
matched to SHOT_LUFS (very short ones by peak). Never edit an .ogg by hand: change this and rerun.

A quiet source is never boosted past MAX_BOOST_DB: matching a 40 dB-down recording to the target lifted
its hiss as much as its sound (the swamp atmospheres were raised 15 to 27 dB), so it lands below the target
instead and the report says so. "dyn" levels a bed with a slow compressor (gusts, a crackle in a hush), "lp"
and "hp" cut hiss and rumble, "fade" is the loop crossfade in seconds (default a quarter of the loop, at most 4).
tools/audit_ambience.py measures the result and flags what is left.
"""
import os, subprocess, sys, re
import numpy as np

BED_LUFS = -30.0
SHOT_LUFS = -26.0
MAX_BED = 90.0
MAX_BOOST_DB = 14.0
BED_PEAK_DB = -9.0
RATE = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "sounds", "ambience")
SLOW_LEVELLER = "dynaudnorm=f=1500:g=31:p=0.8:m=12:s=8"

# out name -> (source file, options). "cut" = (start, end) seconds of the source.
BEDS = {
    "outdoor_night/crickets": ("outdoor_night/crickets_night_loop.mp3", {}),
    "outdoor_night/wind": ("snow_wind/mild_wind_loop.ogg", {"lufs": -36.0, "dyn": True}),
    "indoor_hall/rumble": ("indoor_hall/low_rumble_loop.mp3", {"lp": 1200}),
    "industrial/generator": ("industrial/generator_hum_loop.ogg", {}),
    "industrial/machine_a": ("industrial/machine_08_hum.ogg", {"lufs": -34.0}),
    "industrial/machine_b": ("industrial/machine_11_hum.ogg", {"lufs": -34.0}),
    "cave_tunnel/dungeon": ("cave_tunnel/dungeon_ambient_loop.ogg", {"dyn": True}),
    "cave_tunnel/drip": ("cave_tunnel/basement_drip_loop.ogg", {"lufs": -33.0}),
    "snow_wind/wind_a": ("snow_wind/wind1.ogg", {}),
    "snow_wind/wind_b": ("snow_wind/wind3.ogg", {}),
    "snow_wind/wind_c": ("snow_wind/mild_wind_loop.ogg", {"lufs": -33.0, "dyn": True}),
    "swamp/swamp": ("swamp/swamp_long.ogg", {}),
    "swamp/atmosphere_a": ("swamp/swamp_atmosphere_1.ogg", {"lufs": -34.0, "dyn": True, "lp": 8000}),
    "swamp/atmosphere_b": ("swamp/swamp_atmosphere_2.ogg", {"lufs": -34.0, "dyn": True, "lp": 5000, "hp": 60}),
    "city_ruins/rain": ("city_ruins/rain_gutter_loop.mp3", {"lufs": -33.0}),
    "city_ruins/storm": ("city_ruins/rain_thunder.ogg", {"comp": True, "lufs": -33.0}),
    "city_ruins/siren": ("city_ruins/storm_siren_distant.ogg", {"lufs": -34.0, "dyn": True}),
    "interior_horror/ghostly": ("interior_horror/ghostly_atmosphere.mp3", {}),
    "interior_horror/horror": ("interior_horror/ambient_horror.ogg", {}),
    "interior_horror/dark": ("interior_horror/dark_ambience_1.ogg", {"lufs": -33.0}),
}

SHOTS = {
    "outdoor_night/bird": ("oneshots/bird_night.ogg", {}),
    "outdoor_night/creak": ("oneshots/tree_creak.ogg", {"lufs": -30.0}),
    "outdoor_night/moan_far": ("oneshots/undead_moan_3.ogg", {"lp": 2500, "lufs": -32.0}),
    "indoor_hall/creak_a": ("oneshots/wood_cracking_01.ogg", {"peak": -14.0, "lp": 5000}),
    "indoor_hall/creak_b": ("oneshots/wood_cracking_02.ogg", {"peak": -14.0, "lp": 5000}),
    "indoor_hall/elevator": ("oneshots/old_elevator_door.mp3", {"lufs": -28.0}),
    "indoor_hall/moan_far": ("oneshots/undead_moan_4.ogg", {"lp": 2500, "lufs": -32.0}),
    "industrial/creak": ("oneshots/wood_cracking_02.ogg", {"peak": -12.0, "lp": 5000}),
    "industrial/collapse": ("oneshots/cave_in.ogg", {"lufs": -28.0}),
    "cave_tunnel/collapse": ("oneshots/cave_in.ogg", {"lufs": -28.0}),
    "cave_tunnel/breath": ("oneshots/ghost_breath.ogg", {}),
    "cave_tunnel/moan_a": ("oneshots/ghost_moan_03.ogg", {"lufs": -28.0}),
    "snow_wind/creak": ("oneshots/tree_creak.ogg", {"lufs": -30.0}),
    "snow_wind/moan": ("oneshots/ghost_moan_05.ogg", {"lp": 3000, "lufs": -30.0}),
    "swamp/frog_a": ("oneshots/frog_croak_01.mp3", {"peak": -16.0, "hp": 250}),
    "swamp/frog_b": ("oneshots/frog_croak_03.mp3", {"peak": -16.0, "hp": 250}),
    "swamp/bubbling": ("oneshots/swamp_bubbling_1.ogg", {"lufs": -30.0}),
    "swamp/bird": ("oneshots/bird_night.ogg", {}),
    "city_ruins/moan_a": ("oneshots/undead_moan_1.ogg", {"lp": 3000, "lufs": -30.0}),
    "city_ruins/moan_b": ("oneshots/undead_moan_2.ogg", {"lp": 3000, "lufs": -30.0}),
    "city_ruins/creak": ("oneshots/wood_cracking_01.ogg", {"peak": -14.0, "lp": 5000}),
    "interior_horror/ghost_a": ("oneshots/ghost_moan_01.ogg", {}),
    "interior_horror/ghost_b": ("oneshots/ghost_moan_02.ogg", {}),
    "interior_horror/ghost_c": ("oneshots/ghost_moan_04.ogg", {}),
    "interior_horror/breath": ("oneshots/ghost_breath.ogg", {}),
    "interior_horror/chant_a": ("oneshots/chant_02.ogg", {"lufs": -30.0}),
    "interior_horror/chant_b": ("oneshots/chant_14.ogg", {"lufs": -32.0}),
    # hungry_ghoul is 34 s of moans with a second of silence between: four of them, cut at the gaps.
    "interior_horror/ghoul_a": ("oneshots/hungry_ghoul.ogg", {"cut": (0.0, 4.4), "lufs": -28.0}),
    "interior_horror/ghoul_b": ("oneshots/hungry_ghoul.ogg", {"cut": (5.34, 7.72), "lufs": -28.0}),
    "interior_horror/ghoul_c": ("oneshots/hungry_ghoul.ogg", {"cut": (11.87, 14.23), "lufs": -28.0}),
    "interior_horror/ghoul_d": ("oneshots/hungry_ghoul.ogg", {"cut": (18.35, 20.71), "lufs": -28.0}),
}


def decode(path, channels):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-f", "f32le", "-ac", str(channels),
                          "-ar", str(RATE), "-"], capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.float32).reshape(-1, channels).copy()


def lufs(x):
    raw = x.astype("<f4").tobytes()
    p = subprocess.run(["ffmpeg", "-nostats", "-hide_banner", "-f", "f32le", "-ar", str(RATE),
                        "-ac", str(x.shape[1]), "-i", "-", "-af", "ebur128", "-f", "null", "-"],
                       input=raw, capture_output=True)
    m = re.findall(r"I:\s+(-?[\d.]+) LUFS", p.stderr.decode())
    return float(m[-1]) if m else -70.0


def ffilter(x, af):
    raw = x.astype("<f4").tobytes()
    out = subprocess.run(["ffmpeg", "-v", "error", "-f", "f32le", "-ar", str(RATE), "-ac", str(x.shape[1]),
                          "-i", "-", "-af", af, "-f", "f32le", "-"], input=raw, capture_output=True, check=True).stdout
    return np.frombuffer(out, dtype=np.float32).reshape(-1, x.shape[1]).copy()


def seamless(x, fade):
    n = int(fade * RATE)
    if len(x) < 4 * n:
        n = len(x) // 4
    head, tail, mid = x[:n], x[-n:], x[n:-n]
    t = np.linspace(0.0, np.pi / 2, n)[:, None]
    cross = tail * np.cos(t) + head * np.sin(t)
    return np.concatenate([cross, mid])


def encode(x, path, quality):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    x = np.clip(x, -1.0, 1.0)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(RATE), "-ac", str(x.shape[1]),
                    "-i", "-", "-c:a", "libvorbis", "-q:a", str(quality), path],
                   input=x.astype("<f4").tobytes(), check=True)


def match(x, target, peak_db, max_boost=None):
    got = lufs(x)
    if got > -69.0:
        gain = target - got
        if max_boost is not None:
            gain = min(gain, max_boost)
        x = x * 10 ** (gain / 20)
    pk = np.abs(x).max()
    ceiling = 10 ** (peak_db / 20)
    if pk > ceiling:
        x = x * (ceiling / pk)
    return x, got


def main():
    global OUT
    src = sys.argv[1]
    if "--out" in sys.argv:
        OUT = os.path.abspath(sys.argv[sys.argv.index("--out") + 1])
    report = []
    for name, (f, o) in BEDS.items():
        x = decode(os.path.join(src, f), 2)
        if len(x) > MAX_BED * RATE:
            x = x[: int(MAX_BED * RATE)]
        if o.get("comp"):
            x = ffilter(x, "acompressor=threshold=-30dB:ratio=6:attack=20:release=400")
        if "hp" in o:
            x = ffilter(x, "highpass=f=%d" % o["hp"])
        if "lp" in o:
            x = ffilter(x, "lowpass=f=%d" % o["lp"])
        if o.get("dyn"):
            x = ffilter(x, SLOW_LEVELLER)
        x = seamless(x, o.get("fade", min(4.0, len(x) / RATE / 4)))
        x, got = match(x, o.get("lufs", BED_LUFS), BED_PEAK_DB, MAX_BOOST_DB)
        encode(x, os.path.join(OUT, name + ".ogg"), 2)
        now = lufs(x)
        report.append("bed  %-28s %5.1fs  was %6.1f LUFS, now %6.1f (target %5.1f)%s" % (
            name, len(x) / RATE, got, now, o.get("lufs", BED_LUFS), "  BOOST CAPPED" if now < o.get("lufs", BED_LUFS) - 1.0 else ""))
    for name, (f, o) in SHOTS.items():
        x = decode(os.path.join(src, f), 1)
        if "cut" in o:
            x = x[int(o["cut"][0] * RATE): int(o["cut"][1] * RATE)]
        if "hp" in o:
            x = ffilter(x, "highpass=f=%d" % o["hp"])
        if "lp" in o:
            x = ffilter(x, "lowpass=f=%d" % o["lp"])
        f_in = min(0.03, len(x) / RATE / 4)
        n = int(f_in * RATE)
        ramp = np.linspace(0, 1, n)[:, None]
        x[:n] *= ramp
        x[-n:] *= ramp[::-1]
        if "peak" in o:
            x = x * (10 ** (o["peak"] / 20) / max(np.abs(x).max(), 1e-6))
            got = 0.0
        else:
            x, got = match(x, o.get("lufs", SHOT_LUFS), -9.0)
        encode(x, os.path.join(OUT, name + ".ogg"), 3)
        report.append("shot %-28s %5.1fs  was %6.1f LUFS" % (name, len(x) / RATE, got))
    print("\n".join(report))


main()
