#!/usr/bin/env python3
"""Measures every shipped ambience file and flags the ones a listener would notice for the wrong reasons.

    python3 -I tools/audit_ambience.py                 # table of dot-audio stock/moods/**/*.ogg, exit 1 on a flag
    python3 -I tools/audit_ambience.py --dir /tmp/amb  # a set make_ambience_set.py --out wrote, before it ships
    python3 -I tools/audit_ambience.py --md out.md     # also write the table (docs/ambience-audit.md)

Per file: integrated LUFS (ffmpeg ebur128), loudness range, sample peak, RMS, the share of energy above
6 kHz (hiss), spectral flatness over 1 to 12 kHz (1.0 is white noise), the loop seam step of a bed (jump
between its last and first samples) and the length. A flag is an objective problem; whether a file is
*pleasant* needs a human ear (docs/ambience.md, "What still needs a human ear").
"""
import glob
import os
import re
import subprocess
import sys

import numpy as np

RATE = 44100
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "addons", "dot_audio", "stock", "moods")
SET = ROOT  # moods.json is read from the shipped set; --dir measures files of the same names elsewhere
BED_TARGET = -30.0      # tools/make_ambience_set.py BED_LUFS
SHOT_TARGET = -26.0
INAUDIBLE = -45.0
BED_BAND = 4.0          # LUFS a bed may sit from its target before it is an outlier
SHOT_BAND = 8.0
# Very short one-shots (a crack) are under ebur128's gate and read -70: judged by peak and spectrum only.


def decode(path):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-f", "f32le", "-ac", "1", "-ar", str(RATE), "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.float32)


def ebur(path):
    p = subprocess.run(["ffmpeg", "-nostats", "-hide_banner", "-i", path, "-af", "ebur128=peak=true", "-f", "null", "-"],
                       capture_output=True)
    text = p.stderr.decode()
    tail = text[text.rfind("Summary:"):] if "Summary:" in text else text
    def pick(key):
        m = re.search(key + r":\s+(-?[\d.]+)", tail)
        return float(m.group(1)) if m else float("nan")
    return pick("I"), pick("LRA")


def measure(path):
    x = decode(path)
    lufs, lra = ebur(path)
    rms = 20 * np.log10(max(float(np.sqrt(np.mean(x * x))), 1e-9))
    peak = 20 * np.log10(max(float(np.abs(x).max()), 1e-9))
    n = 1 << int(np.floor(np.log2(max(len(x), 1024))))
    win = np.hanning(2048)
    segs = [x[i:i + 2048] * win for i in range(0, min(len(x), n) - 2048, 4096)][:400] or [np.zeros(2048)]
    spec = np.mean([np.abs(np.fft.rfft(s)) ** 2 for s in segs], axis=0) + 1e-18
    f = np.fft.rfftfreq(2048, 1 / RATE)
    hiss = float(spec[f > 6000].sum() / spec.sum())
    band = spec[(f >= 1000) & (f <= 12000)]
    flat = float(np.exp(np.mean(np.log(band))) / np.mean(band))
    step = float(np.percentile(np.abs(np.diff(x)), 99)) if len(x) > 2 else 1.0
    seam = float(abs(x[-1] - x[0])) / max(step, 1e-6)
    return {"lufs": lufs, "lra": lra, "rms": rms, "peak": peak, "hiss": hiss, "flat": flat, "seam": seam,
            "secs": len(x) / RATE}


def flags(rel, m):
    bed = os.path.basename(rel) and rel in BEDS
    out = []
    target, band = (BED_TARGET, BED_BAND) if bed else (SHOT_TARGET, SHOT_BAND)
    if m["lufs"] > -69 and m["lufs"] > target + band:
        out.append("too loud: %+.1f LU over %.0f" % (m["lufs"] - target, target))
    if m["lufs"] > -69 and bed and m["lufs"] < INAUDIBLE:
        out.append("inaudible bed (%.0f LUFS)" % m["lufs"])
    if not bed and m["peak"] < -20.0 and m["lufs"] < SHOT_TARGET - 3:
        out.append("one-shot peaks only %.0f dBFS" % m["peak"])
    if m["peak"] > -3.0:
        out.append("peak %.1f dBFS" % m["peak"])
    if m["hiss"] > 0.25:
        out.append("hissy (%d%% of energy above 6 kHz)" % round(100 * m["hiss"]))
    if bed and m["seam"] > 1.5:
        out.append("loop seam jump %.1fx a loud sample step" % m["seam"])
    return out


def ear(rel, m):
    """Findings a number cannot settle: the file may be right (a siren is sparse) or wrong; listen."""
    out = []
    bed = rel in BEDS
    if bed and m["lra"] > 12:
        out.append("loudness range %.0f LU: swells or gaps" % m["lra"])
    if bed and m["secs"] < 8:
        out.append("short loop (%.1f s): repeats audibly" % m["secs"])
    if not bed and m["lufs"] > -69 and m["lufs"] < SHOT_TARGET - SHOT_BAND:
        out.append("reads %.0f LU under %.0f: sparse, or too quiet" % (SHOT_TARGET - m["lufs"], SHOT_TARGET))
    return out


BEDS = set()


def main(argv):
    global BEDS
    import json
    global ROOT
    moods = json.load(open(os.path.join(SET, "moods.json")))["moods"]
    if "--dir" in argv:
        ROOT = os.path.abspath(argv[argv.index("--dir") + 1])
    BEDS = {b["file"] for m in moods.values() for b in m["beds"]}
    rows, bad = [], 0
    for path in sorted(glob.glob(os.path.join(ROOT, "*", "*.ogg"))):
        rel = os.path.relpath(path, ROOT)
        m = measure(path)
        fl = flags(rel, m)
        bad += bool(fl)
        rows.append((rel, "bed" if rel in BEDS else "shot", m, fl, ear(rel, m)))
    head = "| File | Kind | Secs | LUFS | LRA | Peak | Hiss >6k | Flatness | Flags | Needs an ear |\n| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |"
    lines = [head]
    for rel, kind, m, fl, ea in rows:
        lines.append("| `%s` | %s | %.1f | %.1f | %.1f | %.1f | %d%% | %.2f | %s | %s |" % (
            rel, kind, m["secs"], m["lufs"], m["lra"], m["peak"], round(100 * m["hiss"]), m["flat"], "; ".join(fl) or "-", "; ".join(ea) or "-"))
    text = "\n".join(lines)
    print(text)
    print("\n%d files, %d flagged" % (len(rows), bad))
    if "--md" in argv:
        open(argv[argv.index("--md") + 1], "w").write(text + "\n")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
