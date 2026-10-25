# Ambience audit

`python3 -I tools/audit_ambience.py --md docs/ambience-audit.md` measures every file of dot-audio's `stock/moods/` with ffmpeg (ebur128 loudness and range, sample peak, the share of energy above 6 kHz, spectral flatness, the loop seam) and exits non-zero on a flag. Flags are hard faults: a bed more than 4 LU over -30 LUFS or under -45, a peak above -3 dBFS, hiss above 25%, a loop seam jump, a one-shot that is both quiet and peaky. `tools/make_ambience_set.py` rebuilds the set with a 14 dB boost cap, a -9 dBFS bed peak ceiling, a slow leveller (`dyn`) on gusty beds, low-pass on creaks and the swamp atmospheres, and a longer loop crossfade. The last column is what a number cannot settle.

| File | Kind | Secs | LUFS | LRA | Peak | Hiss >6k | Flatness | Flags | Needs an ear |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `cave_tunnel/breath.ogg` | shot | 3.4 | -26.2 | 0.0 | -13.3 | 0% | 0.01 | - | - |
| `cave_tunnel/collapse.ogg` | shot | 4.2 | -28.1 | 1.1 | -13.7 | 0% | 0.03 | - | - |
| `cave_tunnel/drip.ogg` | bed | 16.1 | -38.2 | 7.2 | -8.0 | 10% | 0.20 | - | - |
| `cave_tunnel/dungeon.ogg` | bed | 86.0 | -30.0 | 10.5 | -8.7 | 0% | 0.54 | - | - |
| `cave_tunnel/moan_a.ogg` | shot | 5.7 | -28.2 | 5.1 | -8.9 | 0% | 0.00 | - | - |
| `city_ruins/creak.ogg` | shot | 0.2 | -70.0 | 0.0 | -14.3 | 18% | 0.15 | - | - |
| `city_ruins/moan_a.ogg` | shot | 2.3 | -30.0 | 0.0 | -16.6 | 0% | 0.00 | - | - |
| `city_ruins/moan_b.ogg` | shot | 1.9 | -30.0 | 0.0 | -18.3 | 0% | 0.00 | - | - |
| `city_ruins/rain.ogg` | bed | 57.6 | -33.1 | 2.4 | -10.7 | 3% | 0.35 | - | - |
| `city_ruins/siren.ogg` | bed | 81.7 | -34.0 | 16.4 | -15.1 | 7% | 0.78 | - | loudness range 16 LU: swells or gaps |
| `city_ruins/storm.ogg` | bed | 40.4 | -33.1 | 3.2 | -12.9 | 7% | 0.73 | - | - |
| `indoor_hall/creak_a.ogg` | shot | 0.2 | -70.0 | 0.0 | -14.3 | 18% | 0.15 | - | - |
| `indoor_hall/creak_b.ogg` | shot | 0.2 | -70.0 | 0.0 | -14.1 | 11% | 0.14 | - | - |
| `indoor_hall/elevator.ogg` | shot | 3.2 | -28.7 | 20.0 | -8.9 | 0% | 0.21 | - | - |
| `indoor_hall/moan_far.ogg` | shot | 1.5 | -32.1 | 0.0 | -15.3 | 0% | 0.00 | - | - |
| `indoor_hall/rumble.ogg` | bed | 18.7 | -30.1 | 0.4 | -15.0 | 0% | 0.00 | - | - |
| `industrial/collapse.ogg` | shot | 4.2 | -28.1 | 1.1 | -13.7 | 0% | 0.03 | - | - |
| `industrial/creak.ogg` | shot | 0.3 | -70.0 | 0.0 | -12.2 | 11% | 0.14 | - | - |
| `industrial/generator.ogg` | bed | 18.2 | -30.1 | 0.4 | -14.2 | 0% | 0.00 | - | - |
| `industrial/machine_a.ogg` | bed | 3.4 | -34.1 | 20.1 | -15.0 | 0% | 0.04 | - | loudness range 20 LU: swells or gaps; short loop (3.4 s): repeats audibly |
| `industrial/machine_b.ogg` | bed | 4.3 | -34.1 | 0.6 | -20.6 | 0% | 0.10 | - | short loop (4.3 s): repeats audibly |
| `interior_horror/breath.ogg` | shot | 3.4 | -26.2 | 0.0 | -13.3 | 0% | 0.01 | - | - |
| `interior_horror/chant_a.ogg` | shot | 3.0 | -29.9 | 0.0 | -16.4 | 1% | 0.26 | - | - |
| `interior_horror/chant_b.ogg` | shot | 3.5 | -31.9 | 0.4 | -18.2 | 0% | 0.00 | - | - |
| `interior_horror/dark.ogg` | bed | 3.5 | -33.1 | 0.1 | -17.4 | 0% | 0.00 | - | short loop (3.5 s): repeats audibly |
| `interior_horror/ghost_a.ogg` | shot | 3.0 | -26.3 | 20.0 | -9.3 | 0% | 0.00 | - | - |
| `interior_horror/ghost_b.ogg` | shot | 5.2 | -26.3 | 6.1 | -8.6 | 0% | 0.00 | - | - |
| `interior_horror/ghost_c.ogg` | shot | 5.0 | -28.0 | 8.9 | -8.9 | 0% | 0.00 | - | - |
| `interior_horror/ghostly.ogg` | bed | 76.1 | -30.0 | 3.9 | -17.0 | 0% | 0.04 | - | - |
| `interior_horror/ghoul_a.ogg` | shot | 4.4 | -28.1 | 1.6 | -10.7 | 2% | 0.05 | - | - |
| `interior_horror/ghoul_b.ogg` | shot | 2.4 | -28.2 | 0.0 | -11.2 | 1% | 0.04 | - | - |
| `interior_horror/ghoul_c.ogg` | shot | 2.4 | -28.2 | 0.0 | -14.2 | 1% | 0.05 | - | - |
| `interior_horror/ghoul_d.ogg` | shot | 2.4 | -28.2 | 0.0 | -14.2 | 2% | 0.06 | - | - |
| `interior_horror/horror.ogg` | bed | 18.2 | -30.1 | 2.2 | -17.4 | 3% | 0.22 | - | - |
| `outdoor_night/bird.ogg` | shot | 0.8 | -26.1 | 0.0 | -20.4 | 0% | 0.00 | - | - |
| `outdoor_night/creak.ogg` | shot | 6.6 | -34.9 | 8.9 | -9.3 | 2% | 0.12 | - | reads 9 LU under -26: sparse, or too quiet |
| `outdoor_night/crickets.ogg` | bed | 8.6 | -30.5 | 0.4 | -20.4 | 5% | 0.09 | - | - |
| `outdoor_night/moan_far.ogg` | shot | 2.1 | -32.1 | 0.0 | -19.9 | 0% | 0.00 | - | - |
| `outdoor_night/wind.ogg` | bed | 40.5 | -36.8 | 13.0 | -5.9 | 0% | 0.30 | - | loudness range 13 LU: swells or gaps |
| `snow_wind/creak.ogg` | shot | 6.6 | -34.9 | 8.9 | -9.3 | 2% | 0.12 | - | reads 9 LU under -26: sparse, or too quiet |
| `snow_wind/moan.ogg` | shot | 1.7 | -30.0 | 0.0 | -10.9 | 0% | 0.00 | - | - |
| `snow_wind/wind_a.ogg` | bed | 56.0 | -30.0 | 2.6 | -12.9 | 0% | 0.00 | - | - |
| `snow_wind/wind_b.ogg` | bed | 56.0 | -30.0 | 2.6 | -13.4 | 0% | 0.00 | - | - |
| `snow_wind/wind_c.ogg` | bed | 40.5 | -36.8 | 13.0 | -5.9 | 0% | 0.30 | - | loudness range 13 LU: swells or gaps |
| `swamp/atmosphere_a.ogg` | bed | 11.1 | -35.7 | 12.3 | -20.7 | 0% | 0.01 | - | loudness range 12 LU: swells or gaps |
| `swamp/atmosphere_b.ogg` | bed | 18.2 | -44.6 | 17.2 | -28.9 | 1% | 0.11 | - | loudness range 17 LU: swells or gaps |
| `swamp/bird.ogg` | shot | 0.8 | -26.1 | 0.0 | -20.4 | 0% | 0.00 | - | - |
| `swamp/bubbling.ogg` | shot | 6.9 | -33.5 | 6.0 | -8.8 | 0% | 0.05 | - | - |
| `swamp/frog_a.ogg` | shot | 1.0 | -29.4 | 0.0 | -15.8 | 0% | 0.01 | - | - |
| `swamp/frog_b.ogg` | shot | 1.3 | -31.6 | 0.0 | -15.8 | 0% | 0.01 | - | - |
| `swamp/swamp.ogg` | bed | 86.0 | -30.4 | 8.9 | -7.7 | 1% | 0.22 | - | - |

## What still needs a human ear

- **Frogs** (`swamp/frog_a`, `frog_b`): high-passed at 250 Hz from a source that peaks low; check they still read as frogs and are not thin.
- **Siren** (`city_ruins/siren`): loudness range 16 LU because the source is a distant, intermittent siren, not a continuous one. Decide whether the gaps are wanted.
- **Snow winds** (`wind_c`, `outdoor_night/wind`): range 13 LU after levelling; listen for gusts that jump out.
- **`interior_horror/dark`** (3.5 s), **`industrial/machine_a`** (3.4 s) and **`machine_b`** (4.3 s): short loops that may repeat audibly; replace with longer sources if they do.
- **Swamp atmospheres**: `atmosphere_b` is 14 dB boosted from a very quiet source and still sits near -45 LUFS; it may be inaudible under the other beds.
- **Tree creak** (`outdoor_night/creak`, `snow_wind/creak`): one long quiet sound with a short peak, so it reads low by LUFS; check it is heard.
- Whether any file is simply unpleasant. The audit cannot hear.
