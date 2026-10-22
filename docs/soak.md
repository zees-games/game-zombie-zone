# Bot soak

`./game.sh soak [map] [minutes]` runs `tools/soak.tscn`: the map's team of stand-in survivors (`survivors` in the map document; `--bots N` overrides) holds the map in the real `ZzGame` for the given simulated minutes through dot-bot's `DotBotSoak`, with dot-spawn's `DotSpawnWatch` for the stuck and fell-out verdicts. The default map is `zz_high_school`. The world is stepped by hand (`ZzGame.simulate` at 64 Hz), so no `--fixed-fps` is needed and the tick cost is the harness's own time around the step. A stand-in has a goal by `StuckMeter._standin_walks` (a fresh path to somewhere further than a post's reach), so a holder at its post is not stuck. Kills, deaths and damage come from the game's signals, so the harness's kill check is live. The report is `.godot/test-logs/soak-<map>.json` plus one `SOAK {...}` line, and the exit code is 1 on failure. Extra flags (`--soak-max-stuck-sec` and the rest of `DotBotSoakConfig`) pass through.

**Needs the linked `addons/dot_spawn`** (gitignored like the other links, made by dot-bootstrap or `ln -s ../../dot-spawn/addons/dot_spawn addons/dot_spawn`; used by the tool only, never by the game), and an `--import` after adding it.

First run, 2026-10-22, 2 simulated minutes each:

| map | bots | result | kills | stuck max | tick p95 / worst |
| --- | --- | --- | --- | --- | --- |
| zz_high_school | 12 | pass | 75 | 4.5 s | 5.6 ms / 1673 ms |
| zz_lot | 1 | pass | 25 | 0 s | 0.8 ms / 71 ms |
| zz_blackout_1 | 1 | pass | 59 | 4.0 s | 1.2 ms / 49 ms |

- The worst tick on the school (1.7 s) is the round starting (nav graph, map built) falling inside the run, not the hold.
- An exodus map seats 1 stand-in here because its `survivors` is unset; the server seats `zz_exodus_team` (8). Pass `--bots 8` for the server's crowd.
- Two minutes is the warm-up and wave 1 on a survival map; a whole hold is `tools/survival_long_run.tscn`. Run `./game.sh soak zz_high_school 15` for the later waves.
