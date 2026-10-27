# Survival

How a survival map is held, and why each piece is shaped the way it is. The first play test asked for it: "make sure there are maps that also act as survival where all the players spawn in big maps and the humans need to survive until the timer is up (or if configured, could have days, nights, or just rounds) ... By default, make it 10 rounds of hordes ... each round gets harder." And: "There should be many survivors, but it would require the map to be much larger."

## The two modes

A map is **exodus** (from the start shelter to the end one; called "campaign" until the play test asked for a name of its own, and a document that still says `campaign` is read as exodus) or **survival** (hold where you are). The rest of this file is survival.

## The schedule is the director's, the meaning is the game's

dot-npc-ai-director's `DotNpcDirectorWaves` is the schedule: quiet stretches and horde stretches in one of three styles. It spawns nothing; it says what is owed and how hard the stretch is. `game/zz_survival.gd` is what that means here, and `zz_survival` (cvar, `ZzConfig.survival_style`) picks the style:

| Style | Default | Horde stretch | Quiet stretch | Won when |
| --- | --- | --- | --- | --- |
| `waves` | yes, 10 waves | a wave: a count of commons (16 + 4 per survivor, growing), cleared by killing them | a 30 s breather (30 s before the first) | the last wave is cleared |
| `nights` | 5 nights | a night of 150 s: the horde's own pacing (director, mobs, specials, brute) at the night's strength | a 60 s day, the map's `day_environment` light | dawn after the last night |
| `clock` | `zz_survive_seconds` or the map's own | one stretch, harder as it runs (0: as long as anybody lasts) | none | the clock runs out |

**Why the stress cycle is not the hold.** The director's build-up / peak / relax ends its relax on distance travelled, and a team holding a school travels nowhere: the relax never ends. A hold is a schedule; the schedule lives beside the director, not inside it.

**A wave is released, never dropped.** `take()` hands out what the release rate has accrued (1.5 a second in wave 1, faster each wave), within the room the alive cap leaves (`commons_cap`), and what the spawner refuses is owed again (`give_back`). A wave of a hundred on one frame is a hitch and a crowd at one door.

**From the map's edges.** A wave comes from the map's `zombie_spawns` (the car park, the outfield, the tree line), out of sight, fifteen metres or more from everybody, and on ground that reaches somebody; only when no hint will do, from the graph's own points. Drawn from anywhere out of sight, the first school wave came out of the gym's back corner, which nobody was looking at.

**Cleared means dead, with a backstop.** A wave ends when all of it is out and none is alive, 30 s after its last release once three or fewer are left, or 150 s after it whatever is left (`overtime`); then what is left far from everybody is tidied away and the rest are sent at the team. Two commons bashing at a door nobody could see through held a camp's breather off past the minute.

## What makes it ours

- **The breather is a patch-up, not a shop.** The downed get up, the dead come back beside the team, everybody standing gets 30 health, and every cache (`caches` in the map) is cleared and restocked: ammunition, a medkit or pills, a gun from the tier the hold has reached (primaries, heavies past the middle), a throwable from wave 3. No money and no menu: what is on the table goes to whoever walks over.
- **The barricades are the clock that matters** (below). Mending is the breather's other job.
- **Twists** from wave 3, never the same twice running and one wave in three straight: sprinters (a quarter faster), swarm (half as many again, each at 60 % health), heavies (fewer, 180 % health), hunters (half as many specials again). A brute's wave draws none. Announced with the wave and on the HUD.
- **A brute every fifth wave, two with the last** (`zz_brute_every`), each arriving once another third of the wave is out; its wave is not over while it stands, and one left at the overtime leaves rather than carry on into the next.
- **Specials per wave**: one from the second wave and 0.6 more each wave after, for every six survivors, spread over the wave.

## Barricades

A box with a `barricade` id is part of one; `barricades` in the document names it (`label`, `health`). The builder puts them across doorways: planks to the lintel (`door`), planks to chest height (`window`, which the team shoots over and a zombie at the boards can reach across), or one steel sheet (`shutter`).

**On the zombies' ground, on purpose.** A shut gate is cut out of the nav graph so the horde goes round it; a barricade is left in (`"nav": false` on its boxes, and `ZzNpcs.nav_for` skips it), so the horde paths straight at it and is stopped by its boxes. Cut out, a school has no way in: every wave "cannot reach anybody" and nothing ever comes to a window. `headless_maps` checks both faces of every barricade are on the graph.

**Bashing is checked after every kind's own decision** (`zz_zombie_brain._bash_if_barred`): a zombie whose wish points into an intact barricade within 0.75 m of its face stops, faces it, plays its attack, and takes `barricade_bash` (6) a second off it, a special twice that, a brute ten times. The horde answers from a four-metre grid of barricade cells, so a zombie nowhere near one costs a dictionary lookup.

**Mending** is E held on a barricade within reach (2 s, +120); a broken one is rebuilt by the same, unless a zombie stands in the gap, and **never while it is being torn at** (`ZzGame.MEND_LOCKOUT`, 1.5 s after the last blow; "They are tearing at it. Clear them off first."). Without the lockout a mend (60 a second) outran any crowd at a window (6 a second a zombie), and stand-ins behind boards they could not see through mended for ever: in the first long runs no wave on any big map was ever cleared, every one ended on overtime with nobody down. The boards are held by killing what tears at them; mending is the breather's job, or a lull's. Stand-ins skip a barricade being torn at, and shoot a zombie's head when only its head shows over a window's boards (aimed at the chest, every shot went into the planks). The server tells clients each change in sixteenths (BARRICADE), never per hit, and on every round start, because a map played again keeps its document and a client would still draw last round's broken window.

## Many survivors

A map says the team it is built for (`survivors`: school 12, mall 14, ballpark 16, camp 10); unsaid (0) leaves the server's number. With `zz_team_from_map 1` (default) and `bot_quota_mode fill`, stand-ins fill to it when it is more than `bot_quota`; solo, the offline team follows each map. The horde's spawner budget is sized for that team at the map's start, and the commons alive at once grow by 6 per survivor for the first eight and 2 past them (74 for twelve, 82 for sixteen; it was 3 past eight, 78 and 90, and wave 10 measured 16 and 18 ms a tick at that cap).

Stand-ins on a survival map hold **posts** (the map's `posts`, shared out by seat), fight from them, mend the weakest barricade near their post when nothing is in sight (pulsing E, because a mend starts on the press), and in a breather walk to a stocked cache when short of ammunition, a medkit or a primary. Following one leader, twelve of them stood in one corridor with forty windows unwatched.

## The light by day

A survival map can carry `day_environment`; the map's `environment` is its night. `ZzMap` captures both lights once (`_capture_day`) and `set_daylight` blends sun, fill, fog and sky; the client eases toward the hold's `daylight` (sent in SURVIVAL, ramping through a ten-second dawn and dusk). A dawn is a blend, never a rebuild.

## The cost of a crowd

Measured in `headless_survival` (a full team of stand-ins, 75 s of wave 1, on a shared VM at load 6 to 10): school 10.8 ms mean, mall 11.1, ballpark 10.5, camp 9.6, against 15.6 for a 64 Hz tick, worst ticks 50 to 95 ms (a crowd repathing at once); the map start (nav graph of 15 to 18 thousand points) is a one-off 1 to 2 s. Before the three changes below the school was 19 ms. Three things got it there, each found by profiling a tick:

- **A grid of the zombies, built once a tick** (`ZzHorde.zombies_near`). Every chasing zombie's crowd spacing asked the spawner's `npcs_near`, which walks every zombie: ninety each asking every tick was eight thousand position reads and two thirds of the tick. Brains (`neighbours`) and stand-ins (threat scans) ask the grid.
- **Thinking less far off** (`zz_zombie_brain._think_every`): past 20 m from everybody a zombie thinks every second tick, past 45 m every fourth, and one tearing at boards every second; its body moves every tick on its last wish, and the skipped time is handed to the next thought.
- **Stand-ins look in order** (`ZzBots._threat`): candidates scored, the ten best tested for sight in order, the first seen kept for three or four ticks (and "nobody in sight" kept as long), and friends nowhere near the line of fire skipped before their hitboxes.

What is left is the brains' own thinking (path following, the ring, the swing) and `move_and_slide`. A zombie standing still on the floor skips its sweep.

**Wave 10 under budget (zz-survival-tick-budget-1).** The profile said steering; split finer (`--profile` now also prints the six slowest ticks part by part) it was the path search: dot-npc's A* in script was three milliseconds a path, two or three paths a tick, and a crowd repathing together was the 170 ms tick. What changed, largest first:

- **Native A*** in dot-npc (`AStar3D`), and smoothing only a path's first 16 points (`smooth_horizon`): paths went from 7.6 ms a tick to under one.
- **The first spawn of each kind compiled its brain**, 30 ms, every time a special came (the spikes at a wave's specials): `spawner.warm()` at map load, and dot-npc holds what it loads.
- **A special's spot tested sight before score** (`_spawn_point`): up to ninety candidates times twelve survivors' eyes. Scored first, the best unseen kept; the same answer.
- **Bodies far off move every second tick** (`ZzZombieBody.stride`, past 30 m), twice as far; brains think every third tick past 20 m (every fourth past 45).
- **`surround` asked the squad once a waiter**, an O(n²) walk with a copy per question; dot-npc-ai now shares it per tick.

Measured `--from=10 --profile`, seed 1, before (all four repos stashed, VM load 2.5) and after (load 4 to 7): school 16.5 → 9.1 ms mean, worst 140 → 22; mall 17.4 → 10.0 to 10.2, worst over 100 → 24 to 33; ballpark 18.9 → 8.7, worst 150 → 25. After, brains are 2.2 to 2.5 ms, bodies 1.0 to 2.2, perception 0.8 to 1.1, and the stand-ins (bots and players) about 2. `headless_survival`'s wave-1 minute is 2.4 to 4.4 ms on every big map. The slowest ticks left are a few parts at once over their means, which is the machine more than the game.

**A solo frame on a converted map (zz-perf, 2026-10-23).** Reported at wave 7 on zm_abandoned_mall, solo with 56 zombies: 35 fps, physics 15.6 ms over 1.7 steps, 6013 draws. `tools/shot_bench.sh` is the fixed-seed benchmark (`--zombies=56 --seed=7`, every zombie forced onto the player from 8 to 40 m out, 20 s measured after 4 s; `--profile` adds the tick by part); it prints one BENCH line and runs on a GPU box through `../gpu.sh shot`. On the laptop box (GTX 1660 Ti, Forward+ under Xvfb), the same seed before and after (the box is shared: its GPU time ranged 9 to 20 ms between runs, so compare physics and draws first):

| zm_abandoned_mall | fps | frame ms (p99) | physics ms (steps) | render ms | draws | objects |
| --- | --- | --- | --- | --- | --- | --- |
| 56 zombies, before | 9.0 | 110.8 (165) | 72.2 (6.6) | 31.8 | 3173 | 5010 |
| 56 zombies, after | 16.9 | 59.2 (108) | 36.0 (3.5) | 17.0 | 1497 | 2384 |
| no zombies, before | 39.5 | 25.3 (38.5) | 4.9 (1.5) | 17.2 | 3007 | 4829 |
| no zombies, after | 42.1 | 23.8 (29.4) | 4.9 (1.4) | 15.6 | 1312 | 2149 |

- **The frame is a spiral, not a sum.** Solo, the game's tick runs in the physics step, and a frame owes one step per 16.7 ms it took: a frame of R ms of drawing with a tick of T ms settles at R / (1 − T / 16.7). The reported 28 ms is about that formula with R 12 and T 9.2, and every millisecond off the tick is worth two or three off the frame.
- **One draw per material, not per brush face** (dot-map's `build_meshes`): a world chunk's faces that share a material are one surface. Draws halved and the render went from 32 to 17 ms.
- **Stand-in props are drawn to a range by their size** (dot-map's `prop_view_per_metre`, 60 m per metre, at least 30 m): a can is gone at 30 m, a shelf at 120.
- **A body pressed against a wall stops testing a step-up there** (`ZzZombieBody._step_up`) until it moves or turns: the three lifted sweeps per failed step were a third of the bodies' cost in a crowd at the shop fronts.
- **Crowd detail** (client, Video, `crowd_detail`: Low, Normal, High; `npcs/zz_zombie_lod.gd`): a zombie is animated every frame within 22 m, every second to 45 m and every fourth past it, every eighth outside the view, casts no shadow past 30 m and is not drawn past 120 m (Normal; Low 12/25/15/70, High 40/80/60/160). Normal is the old animation distances, so near zombies look the same.
- **`zz_zombie_think_range`** (server, default 1) scales the distances past which zombies think and step less often. It saves little in this benchmark: a crowd in reach swings, and a swinging zombie thinks every tick.

**The crowd's tick (zz-crowd-tick, 2026-10-24).** Same bench and box (shared with other runs; best of four baseline runs shown), plus the tick by part headless on the dev VM:

| zm_abandoned_mall, 56 zombies | fps | frame ms (p99) | physics ms (steps) | render ms | brains ms/tick | bodies ms/tick |
| --- | --- | --- | --- | --- | --- | --- |
| before | 9.6 | 104.0 (150) | 70.0 (6.2) | 27.8 | 3.13 | 1.71 |
| spacing grid | - | - | - | - | 3.03 | 1.46 |
| horde per frame (solo) | 15.9 | 62.7 (83) | 28.1 (3.8) | 28.3 | - | - |
| both, with the dropped swing tier | 15.9 | 63.1 (94) | 27.7 (3.8) | 29.0 | 3.07 | 1.80 |

- **Crowd spacing asks a spatial hash** (dot-npc-ai's `DotNpcAiCrowdGrid`, through the brain's `separation` hook): the horde's grid holds each zombie's index, and a brain's spacing reads its neighbours' stored positions instead of a list built per question. Small: about 0.1 ms off the brains and 0.25 off the bodies.
- **Solo, the horde ticks once a drawn frame** (`ZzGame._tick_horde`, `ZzConfig.horde_frame_ticks`, default 4): the physics steps a slow frame owes still move survivors, but the horde ticks once with the time they covered (at most four ticks of it). The spiral was the horde's 7 ms paid per step; now it is paid per frame, so physics fell from 70 to 28 ms and fps rose 1.66 times at the same render. Online and headless nothing changes: the server keeps one horde tick a step.
- **Tried and dropped: a swinging zombie thinking every second tick.** Within the noise on both machines, and it moved which zombies reach the chokes in `headless_nav`.
- **No shared flow field**: path steps were about 0.6 ms of the 7.9 ms headless tick (brains 3.0, bodies 1.5, senses 0.7, survivor 0.95, stand-ins 0.6, weapons 0.35), so one field for the crowd would save under a tenth.
- **Jolt** (`3d/physics_engine`, not switched): the same tick headless, bodies 1.80 → 1.27 ms and the survivor 0.99 → 0.88, physics 3.8 → 3.3 ms; the web templates include it. It changes how a body slides along and steps up walls, so switching it is a decision of its own, after a play-test.

**Where a 1660 Ti frame's "physics" goes (2026-10-25, `shot_bench --zombies=N`, now printing MONITORS and `--micro`):** 56 zombies are 67 ms a frame: physics 35 (the scripts' `_physics_process` 28, the engine's step the other 7), render 25. A frame is 4 ticks (15 fps), and each tick costs the 8 survivors alone 5.9 ms with no zombie (motor `simulate_tick` 260 µs a survivor, `bots.drive` 390 µs, weapons 310 µs), so 4 ticks of that are 70% of the 10.5 ms physics with 0 zombies and a third of the 35. Solid props are not it: the mall has 10 boxes, the tunnel none, and the tunnel is as slow (31 against 38 ms). 150 zombies cap at 66 alive with 8 survivors and cost the same (37 ms). Jolt: 61 ms wall, physics 29 (3.65 steps), a 10% gain, not switched.

60 fps here is out of reach on this box: under Xvfb the render alone is 28 ms. On the box the frame is now render plus one horde tick plus the physics steps' survivors and stand-ins.

What is left is the tick: about 120 µs of script per zombie per tick on this CPU (thinking 70, of which the path step is 55 µs a call, the body's sweep 55 µs, senses 17), so 56 zombies in reach are 7 ms of the 10 ms tick, and the solo player and stand-ins most of the rest. 60 fps needs that tick near 4 ms; 100 needs it near 2 ms and a render near 7, which is the crowd stepped in native code, not more distance tiers. The physics engine's own `move_and_slide` costs 40% less under Jolt in a 56-capsule measurement; the game still runs GodotPhysics3D. Under Xvfb the laptop's render is about 6 ms more than its GPU time (15.6 against 7.7 with no zombies), so a frame on a desktop is faster than these numbers.

**Wave 7 with 120 zombies, solo (zz-perf-client, 2026-10-25).** Reported on a desktop at about 40 fps with physics 11 to 14 ms over 1.2 steps and render 3.8 ms: the tick, not the drawing. Same bench on the laptop box, `--zz-map-ids=zz_high_school --zombies=120 --measure=20` (about 74 alive), two runs each:

| zz_high_school, 120 zombies | fps | frame ms (p99) | physics ms (steps) | `_physics_process` ms | render ms |
| --- | --- | --- | --- | --- | --- |
| before | 13.4, 13.7 | 74.7, 72.9 (112, 95) | 34.8, 32.7 (4.5, 4.4) | 23.7, 22.5 | 31.7, 32.1 |
| after | 15.5, 15.8 | 64.7, 63.3 (95, 95) | 27.3, 26.7 (3.9, 3.8) | 20.9, 19.4 | 29.3, 28.7 |

The tick by part (`--profile`, ms a tick): stand-ins 1.92 → 1.37, the survivor 1.77 → 1.61, weapons 0.91 → 0.52, brains 3.89 → 3.68, bodies 1.41 → 1.27, senses about 1.5 and the grid 0.4 unchanged; about 12.4 → 11.1. What changed:

- **Smoothing remembers a leg** (dot-npc's `memo_legs`): a crowd chasing one survivor smooths the same legs again and again, and `can_walk_straight` was most of it. The stand-ins smooth only their path's first 16 points (`ZzBots.SMOOTH_HORIZON`).
- **A stand-in's threat scan** sorts packed integer keys instead of a lambda over dictionaries, and the crowd grid answers a 32 m question by walking its entries rather than a thousand cells.
- **A squad delivers each enemy's newest report** without walking the whole log since the member last asked.
- **A severed limb's cut is cached per body mesh and bone** (dot-npc's `DotNpcGibs`): every sever was two script skinning passes, about 8 ms; the same cut again is 0.3 ms, with the same triangles.

90 fps is not reachable on this box: the render alone is 28 to 31 ms under Xvfb, and the tick is still about 11 ms with the cost spread over every part of a zombie's thought (sensing and listening 1.2 ms, deciding 1.7, the rest under 0.3 each). It needs the crowd stepped in native code, behind a cvar and off by default, and a cheaper zombie render. `tools/perf_budget.sh` now has the case `zz_high_school@120`.

**Few zombies in sight, still 40 fps (zz-perf-shadows, 2026-10-26).** With no zombie the tick is about 3 ms (`shot_bench --profile`), so the cost is the drawing, and `tools/bench.gd --without=<kinds>` and `--census` say where: on zs_verystill (GTX 1660 Ti, Compatibility, 1280x720) turning the sun's shadow off cuts 3006 draws to 699 and 449k primitives to 98k, while decals, multimeshes, lamps' glow and fog change nothing. The shadow pass redraws every caster once per cascade (4 by default) and the 1000 or so library props each cast. Two client settings, `sun_shadow_splits` (default 2; 4 is the old look) and `prop_shadow_min` (default 1.2 m; props smaller than that cast no sun shadow; 0 is the old look), took zs_verystill from 3006 draws and 449k primitives to 1782 and 286k and zm_abandoned_mall from 1919 draws and 368k to 1037 and 235k (wall 34.6 to 32.6 ms; the box is shared, so frame times move a few ms between runs and draws are the figure to trust). A frame rendered before and after differs in under 1% of its pixels. Splits at 1 would give 1765 draws without the props; shadow distance changes draws little because a world chunk is one caster the size of a street.

**Few zombies in sight, the real cost (zz-perf-lod, 2026-10-26).** The shadow work above left zs_verystill at 33 million primitives a frame: `bench.gd --census` now prints the triangles by holder (`TRIS`), and 23.7 million were 13 scanned island trees of 1.6 million triangles each, 3.9 million jacaranda trees, 3.1 million air ducts, with no LOD (a glTF read at run time has none; only the editor's import makes them). dot-map's `DotMapBspMesh.add_mesh_lods` now cuts a library mesh over `prop_max_tris` (150000) to the first simplification that fits and gives it LOD levels (meshoptimizer; about a second for a million triangles, once per model) when it has `prop_lod_min_tris` (20000) or more; `mesh_lod_threshold` (1.0, the engine's own) is the viewport's LOD bias. GTX 1660 Ti, Compatibility, 1280x720, 5 zombies, `--zz-prop-lod-min-tris=0` (before) against the defaults, one run each (the box is shared):

| map | primitives k | GPU ms | draws | wall ms |
| --- | --- | --- | --- | --- |
| zs_verystill | 33242 to 3379 | 22.2 to 14.9 | 1066 to 1118 | 56.7 to 48.7 |
| zm_abandoned_mall | 4978 to 1026 | 13.2 to 13.5 | 680 to 696 | 46.8 to 48.6 |
| zs_ravenstreet | 101 to 95 | 8.6 to 8.1 | 202 to 195 | 26.5 to 25.7 |

With the shadows off after the change the GPU time stays at 14 ms, so what is left on verystill is the box's Xvfb floor (11 to 14 ms with nothing drawn). The tick is the rest: 5.6 ms (`--profile`: players 1.5, bots 1.0, world 1.2, weapons 0.4, horde 1.7) at 2.5 steps a frame on the mall with 5 zombies.

**The tick at 100 survivors and 248 zombies (zz-tick-cost, 2026-10-26).** `survival_long_run --profile` now splits the players and the world (`p.simulate`, `w.bodies`). Two finds: `ZzFooting.floor_plane` walked every nav floor, spawn and water box per survivor per tick (0.55 ms a tick for 8 survivors, 0.07 after, cached on the map), and the stand-ins rebuilt `survivors()` and walked it for every pinned-friend, downed-friend and caches-with-loot question, ten thousand times a tick at 100 (`ZzBots` now reads the roster, the pinned and downed lists and the stocked caches once per `drive`). `server_probe --n=100 --acks --lead=45`, 64 Hz, ms a tick: bots 11.95 to 7.8 (7.77, 7.92), total 63.95 to 58.8 and 59.9; brains 8.6, players 8.3 (the motor, 80 µs a survivor), snapshots 16.5 (native) unchanged. `--npc-workers=2` (sense and path workers) measured no gain here (brains 8.64 to 9.71, total 63.95 to 65.54: paths are 0.6 ms of the tick and the brains' reads of nodes cannot leave the main thread), so `sv_threads_npc` stays off. The tick is still 4 times the 15.6 ms budget at 100; what is left is the motor and the brains' per-zombie script.

**Interest and threads at 100 (zz-tick-cost, 2026-10-26).** Laps inside the brains put the players-times-zombies terms in perception and the squad: about 520 sight rays a tick (24 candidates a zombie, each tested until one is seen), each thinking zombie taking every squadmate's newest report on every survivor (`DotNpcAiSquad.pull`, 1.3 ms), and its sound queue (0.35 ms). dot-npc now tests the committed target first and only rivals that could take over (`DotNpcSenses.prune_by_held`, exact: 15% fewer rays). The NPC workers gave nothing because only the ranking (0.75 ms) and path searches (0.6 ms) can leave the main thread; the rays and the brains read nodes and the physics space. Snapshot build workers (`sv_threads_net`, default 0) are the thread path that pays. Distance thinning buys little because nearly every zombie is within 40 m of somebody (97% of samples): `npc_lod 1` saved nothing and changed kills (93 to 90), and snapshot thinning past 20 or 40 m every second snapshot raised bytes 22% for 1 ms; every fourth past 15 m in two bands cut bytes 29% and the build 7 ms but leaves a far zombie 130 to 270 ms between updates against a 66 ms buffer, so `zz_net_far_every` stays 1. `server_probe --n=100 --acks --lead=45`, ms a tick, kills 78 and damage 4058 in every row:

| run | total | brains | senses | players | bots | net snapshot | bytes/s/peer |
| --- | --- | --- | --- | --- | --- | --- | --- |
| before | 60.90 | 9.75 | 4.83 | 8.29 | 8.06 | 16.48 | 98375 |
| held-first senses | 59.08 | 9.62 | 4.40 | 8.17 | 7.89 | 15.99 | 98375 |
| and `--workers=2` | 50.01 | 8.70 | 4.43 | 8.24 | 7.91 | 7.83 | 96027 |
| and `--workers=4` | 49.33 | 8.68 | 4.40 | 8.20 | 7.89 | 7.03 | 95661 |

Then (zz-tick-cost, `tickcut`): `DotNpcAiSquad.pull` walks the log rows since the member's last think when that is fewer than the enemies (one pass in log order, no dictionary walk and no sort), the same deliveries by a selftest section that checks both paths against a brute-force reading at 100 enemies. Laps put the pull at 8.6 µs a call and 1.2 ms a tick (was 1.3): what is left is `DotNpcAiMemory.informed` per delivered report, real news each time, so a cap or a shared memory would change what zombies know and kills; a batched `_squad_report_rows` call measured no faster and was dropped. The attack move (`steer_with_spacing`: path advance, crowd-grid separation, `steer_toward`, progress watch) and `_listen` (already early-outs when no sound is new) are a dozen small calls each with no single term to cut, so 3.1 and 0.35 ms stand; cutting them further wants the crowd stepped natively. Same probe, kills 78 and damage 4058 identical:

| run | total | brains | senses | players | bots |
| --- | --- | --- | --- | --- | --- |
| before (this session) | 56.63 | 8.56 | 4.42 | 8.02 | 7.80 |
| pull by log row | 55.67 | 8.44 | 4.39 | 7.98 | 7.71 |

Still three times the budget: the players' motor (80 µs a survivor), the brains' per-zombie script (zz decide 4.5 ms, of it the attack move 3.1) and the stand-ins, which a server of humans does not pay.

## Ten waves, played (zz-survival-long-run-1, 2026-10-12)

`tools/survival_long_run.tscn` plays a whole hold on one map with its full team of stand-ins, headless, and prints a row per wave: seconds, sent, most alive, downs and deaths (and what downed them), barricades broken, the team up at its end, the tick's mean and worst, and a `RESULT` JSON line. `--from=K` starts at wave K (barricades whole, nobody hurt, the caches at K's tier), `--profile` splits the tick by part, `--watch=S --detail` says where the wave's zombies are and why. A school's ten waves are about 35 minutes of play and longer than that on a shared VM, so the runs were split: from wave 1 as far as nine minutes go, and from 4, 7, 9 and 10, several seeds, eight at a time.

What they showed, on normal, before tuning:

- **Every wave ended on overtime** (about 200 s each) with nobody down: the mend stalemate above. With the lockout and the head shots, waves 1 to 3 clear or nearly clear in 120 to 200 s with 0 to 4 downs on every map.
- **The loss comes in a burst, between waves 5 and 9**: a brute wave or a twist with specials (hunters, heavies) downs ten or more at once and the rest go down within a minute. Downs are mostly commons in the gaps, then rams, brutes and leapers. From a fresh start at wave 7 the camp lost at 7, 8 and 8, the school at 8, the mall at 7; from 9, the school and the camp at 9; from 10 the school won once in three.
- **The ballpark was too easy**, and its waves stalled (fixed by zz-stadium-stalled-waves-1, below).

Tuned from it: `wave_growth` 0.25 → 0.22 and `wave_growth_accel` 0.02 → 0.018 (wave 10 is 4.4 times wave 1, was 4.9), the mend lockout, and the cap past eight survivors. After: from wave 1 the camp held every wave the nine minutes reached on two seeds (to 4 and to 5; before the change one seed was lost at 5 to a hunters wave with a brute), from 4 the school held 4 and 5 and the mall 4, from 7 the camp held 7 and 8, the school 7, and the mall lost at 7. So a team of stand-ins usually reaches wave 7 or 8 and clearing ten is rare, which is the aim; `barricade_health` (500), `barricade_bash` (6), `barricade_repair` (120) and `breather_seconds` (30) stay. Each segment starts with whole barricades, so a hold reached from wave 1 is a little harder than these say.

**The ballpark's stalled waves (zz-stadium-stalled-waves-1).** `--watch --detail` (which now also lists still zombies far off with their path, and the spawns refused and why) found four things, none of them the ballpark's alone:

- **Wanderers held the cap.** Map commons are placed by floor area up to 80 % of the commons cap; the ballpark's area put about sixty-five idle in the far stands, and a wave had seventeen places: its spawns were refused for minutes and `sent` fell back by what was owed again. A survival map's wanderers now take at most a fifth of the cap (`ZzHorde.SURVIVAL_WANDERER_SHARE`) and what is left of them is sent at the team as each wave begins (`send_map_commons`).
- **A release counted no queue.** Each tick took the room again while the last tick's were still queued; `_release` now leaves room for `pending_commons()`. What the spawner still refuses mid-wave are a screamer's or bile's mob at a full cap, which is harmless.
- **Hurt specials retreated for ever**: hurt below 35 % they broke off, came back, and broke off again on the next thought, pressed against the outfield wall. A special breaks off again only once hurt further (`_retreated_at_health`).
- **Doors.** A dugout bench stood across its tunnel's door (zombie-zone-maps), smoothed paths clipped door jambs (dot-npc's corner probe, and `go_rough` when a zombie makes no headway), a stuck common hopped toward its target rather than its path, and a zombie in the corner of a window, pressed along it, never bashed (`barricade_in_way` now asks toward the nearest point of the boards, not their middle).

After, from wave 7 on seed 1: the whole wave is sent with no refusals of its own, the horde reaches the posts (thirty to sixty within six metres), and wave 7 took 16 downs and 16 deaths, wave 8 (swarm) 8 and 6, against 0 to 4 before. Wave 7 still ended on its overtime with the team nearly all down and a few left far off.

**Waves are harder everywhere since.** The wanderer share and the queue fix give every map's waves the room under the cap they were meant to have (before, most of the school's and mall's cap was wanderers too). Continuous holds from wave 1, no `--from` (zz-survival-continuous-run-1, normal, sixteen to ten stand-ins; each ended in under ten minutes because it was lost), wave reached:

| Map | Seed 1 | Seed 2 |
| --- | --- | --- |
| School (12) | lost in 6 (sprinters: spitters, commons) | lost in 5 (hunters) |
| Mall (14) | lost in 6 (heavies) | lost in 5 (hunters) |
| Ballpark (16) | lost in 7 | lost in 4 (rams, leapers, a hazard) |
| Camp (10) | lost in 5 (heavies) | lost in 6 (swarm) |

Waves 1 to 3 still go by with 0 to 5 downs; the loss comes in one wave, as before, but at 4 to 7 rather than 7 or 8. So the tuning is not confirmed: the aim (a stand-in team usually reaches 7 or 8, a clear is rare) wants gentler numbers now that the waves fill the cap. One trial of `wave_growth` 0.18 / `wave_growth_accel` 0.014 on the school's seed 1 was lost at 2, which says one seed says little; the retune wants several seeds a setting (done below).

## Retuned from continuous holds (zz-survival-retune-1, 2026-10-12)

Continuous holds from wave 1 (no `--from`), normal, the map's full team of stand-ins, seeds 3 to 8; each run was capped at ten minutes of a shared VM's time (load 6 to 13, eight at once), so a hold still going then is written "reached N". Before the changes, seeds 3 and 4: school lost in 4 and 3, the camp in 7 and 6, the mall and the ballpark still in waves 5 and 4 at the limit.

What the runs showed, in order of weight:

- **Mobs ignored the wave's room.** A bile splash (a mob of 0.8 × 14 + 3 a survivor, about forty for a dozen), a screamer and a box's mob were spawned on top of the wave, up to the server's whole cap: third waves peaked at 74 to 82 alive while the release itself held 40, and those were the holds lost in wave 2 or 3. A survival wave now sets `ZzHorde.wave_room` and `spawn_mob` fits under it.
- **The whole cap from wave 1.** A wave may have `wave_alive_share` (0.4) of the commons cap up at once in its first wave, growing on a square curve to all of it by the last (half of it by wave 6, four fifths by wave 8): the middle waves, where holds ended, are gentler and the last one is still the wall.
- **Too many specials.** One more each wave past the first for every six survivors, not four (`survivors_per_wave_special`): a dozen met thirteen specials in a wave-3 hunters twist. Hunters bring half as many again, not twice.
- **A brute on top of a twist.** Wave 5 (brute plus sprinters or a swarm) was where most of the first tuned runs ended; a brute's wave now draws no twist. Sprinters are a quarter faster, not a third.
- **Every wave ran to its overtime** with four to eight commons left somewhere far off. A wave down to half the team's number in stragglers (`wave_straggler_share`, never under three) ends 30 s after its last release, as three did; the breather's tidy-up then clears them.

After (the defaults now), wave reached or lost in:

| Map (team) | 3 | 4 | 5 | 6 | 7 | 8 | Median |
| --- | --- | --- | --- | --- | --- | --- | --- |
| School (12) | reached 8 | reached 8 | lost in 6 (swarm) | lost in 6 (sprinters) | lost in 6 (heavies) | lost in 6 (hunters) | 6 |
| Mall (14) | reached 7 | lost in 4 | reached 7 | reached 8 | lost in 4 | reached 8 | 7 |
| Ballpark (16) | reached 9 | lost in 6 (swarm) | lost in 6 (heavies) | reached 9 | lost in 6 (heavies) | lost in 7 | 6.5 |
| Camp (10) | lost in 8 (sprinters) | lost in 5 | lost in 5 | **won** | lost in 9 (heavies) | lost in 9 (heavies) | 8.5 |

Over all 24 the median team reaches wave 7 and one cleared all ten, which is the aim; the spread on one map is as wide as between maps, so a single seed says little. The school and the ballpark still most often go down in wave 6, a twist wave right after the brute's; that is the next thing to look at (queued as zz-survival-retune-2). A trial at `wave_alive_share` 0.35 (seeds 3 and 4) was not clearly easier and was not kept. `wave_growth` (0.22), `wave_growth_accel` (0.018), the release rate, the breather (30 s, `breather_heal` 30) and the barricade numbers stay.

**The tick at wave 10, the crowd at the cap, before the work above** (`--from=10 --profile`, on a VM shared with other sessions at load 7 to 11): school 18.8 ms mean, mall 18.2, ballpark 16.4, camp 10.6, against 15.6; alone at load 3 the school was 15.0 ms at the old cap. The zombies' brains are 6 to 7 ms of it (the chase, the ring and the crowd spacing in dot-npc-ai's steering, not perception, which is 1 ms) and their bodies 3 to 4; the worst ticks, 165 to 175 ms, are brains (a crowd repathing at once). Thinking every second tick from 6 m out instead of 20 changed the brains by half a millisecond. It is now under budget (above).

## The brute that outlived its wave (zz-survival-retune-2, 2026-10-13)

The same holds (continuous from wave 1, normal, the map's full team, seeds 3 to 8), now one at a time and in the background, so a hold runs to its end rather than to a ten-minute limit. The long run's wave rows now also say which barricades broke (`broke`) and the post nearest each survivor downed (`by post`, an index into the map's `posts`).

**What the rows showed.** Before any change, at the tree's state that morning (toys, the deeper ground slabs and the rest landed since retune-1), the school and the mall had a median of 7, the camp 8 and the ballpark 9: the school no longer ended in 6 most often, and the ballpark had become the easy one. But the waves lost after a brute's were lost to a brute: over the 24 holds, 52 downs by a brute in waves that bring none (seed 8's school lost wave 6, hunters, with eight of its twelve downs by a brute). A wave down to its stragglers ends 30 s after its last release, and the brute was one of the stragglers; the overtime tidy-up then sent everything near the team at it, so the brute went on through the breather into the twist wave after.

**What changed.** A wave is not down to its stragglers while its brute stands (`ZzHorde.wave_brutes`; the overtime still ends it), and a brute still standing when its wave ends leaves with the far stragglers (`clear_wave_stragglers`). After, 7 downs by a brute outside a brute's wave in 24 holds.

| Map (team) | 3 | 4 | 5 | 6 | 7 | 8 | Median | Before |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| School (12) | lost in 8 (sprinters) | lost in 7 | lost in 7 | lost in 8 (hunters) | lost in 6 (heavies) | lost in 9 (hunters) | 7.5 | 5, 7, 7, 7, 9, 6: 7 |
| Mall (14) | lost in 7 | lost in 7 | lost in 7 | lost in 6 (hunters) | lost in 10 | lost in 8 (heavies) | 7 | 9, 7, 9, 7, 6, 6: 7 |
| Ballpark (16) | lost in 6 (heavies) | lost in 8 (heavies) | lost in 9 (swarm) | **won** | lost in 9 (heavies) | lost in 8 (hunters) | 8.5 | won, 8, 9, 10, 9, 8: 9 |
| Camp (10) | lost in 8 (sprinters) | lost in 8 (swarm) | lost in 5 | lost in 7 | lost in 9 (heavies) | lost in 9 (sprinters) | 8 | 10, 8, 8, 7, 9, 5: 8 |

Every map's median is in the 7 to 8 band the aim asks for (the ballpark at its top), the camp and the mall where they were, and over all 24 the median is still 8 with one hold cleared. One seed moves a map's row by two waves either way (the ballpark's seed 3 went from a clear to a loss in 6 with nothing on that map changed but the brute), so read a map's median, never a cell.

**Tried and not kept: posts that cover the barricades.** The school's twelve stand-ins take the first twelve of its sixteen posts, which leaves the main doors, the west doors and the loading door with nobody, and those are the barricades broken most (`broke`). Choosing the twelve posts that leave the fewest barricades unseen (a classroom post that faced no window and a second gym post went, the doors were held) made it worse: seeds 3 to 6 lost in 8, 5, 4 and 6 against 5, 7, 7 and 7. Spread to the ends of an 80 m hall, the stand-ins were too far apart to help each other; bunched in the middle they hold the hall, and the doors breaking is the horde coming to them.

**Seen, not changed: the whole team goes to one friend.** A stand-in goes to any friend pinned (from anywhere) or down (within 40 m), so on the ballpark one ram at a dugout downed the whole team as it came across the field, seventeen downs at one post in a wave, and the same at the school's library and the camp's posts. It is what decides most ballpark and camp losses; answering with the nearest two would make every map easier, so it waits for a retune of its own (queued as zz-bots-helpers-1).

## Bots on the navigation notes

`ZzNavNotes` bakes each map's navigation mesh (`DotBotNav.bake`), waits two physics frames for the colliders, runs `DotNpcAiNavAnnotator` seeded with the spawns and caches the result in `user://nav/`. Cold annotation takes 0.25 s (chapel) to 4.6 s (stadium) and is sliced by a time budget; bake takes 25 to 380 ms. The finder's defaults found no chokes on these maps, so the notes use choke width 4.5, traffic 0.07 and 192 random routes.

Stand-ins hold a choke (stand `HOLD_BEHIND` metres behind it, or at cover within `COVER_WITHIN`) and leave for another place when `zz_bot_hold_overrun` zombies stand on it, returning when the crowd is gone. Barricade use and `zz_pass_barricades` are unchanged. Share of stand-ins within 7 m of a route choke before the wave, holds on against posts alone: high school 1.00 vs 0.25, mall 0.93 vs 0.36, stadium 1.00 vs 0.31, relief camp 1.00 vs 0.20, chapel 1.00 vs 1.00 (its posts were already at chokes), lot 1.00 vs 0.75.

Zombies pick a choke by traffic share (`zz_zombie_spread`): on the high school they go through 6 chokes, none above 28 percent (off: one line), on the mall through 13, none above 10 percent. `ZzNavGraph` adds one-way drop edges (`zz_nav_drop_max`) and optional climb edges (`zz_zombie_climb`); stand-ins route with `bot_filter` and use neither. **Every shipped map has floors at y=0 only, so drops apply 0 times today**; the mechanism is tested on a synthetic two-floor graph.

`tools/nav_render.tscn` writes the debug top-down and a frame of humans holding a choke to `screenshots/`.

## One friend, two answerers (zz-bots-helpers-1, 2026-10-15)

`ZzBots._pinned_friend` answered a pinned friend from anywhere and `_downed_friend` a downed one within 40 m, so the whole team walked to one friend and went down at one post (a ram at a ballpark dugout downed all sixteen). On a survival map only the `bot_helpers` (`zz_bot_helpers`, 2) nearest standing survivors now answer, and anybody within `bot_helper_radius` (`zz_bot_helper_radius`, 8 m); the rest hold their posts. `bot_helpers 0` is the old behaviour, and exodus maps are unchanged.

Continuous holds, seeds 3 to 8, normal, full team (wave lost in; won is 10+):

| Map (team) | 3 | 4 | 5 | 6 | 7 | 8 | Median | Before |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| School (12) | 10 | 10 | 8 | 9 | 8 | 10 | 9.5 | 7.5 |
| Mall (14) | 10 | 8 | 10 | 8 | 6 | 7 | 8 | 7 |
| Ballpark (16) | won | won | won | won | won | 9 | won | 8.5 |
| Camp (10) | 4 | 10 | 5 | 10 | 4 | 7 | 6 | 8 |

Every map but the camp is easier, as expected (the ballpark is cleared five times in six), and the camp is harder (three of six lost by wave 5, with ten survivors two answerers are a fifth of the team).

**Retuned (same day).** Two per-map tables in `ZzConfig`: `wave_scale_by_map` (a wave's size, school 1.3, mall 1.15, camp 0.85, ballpark 1.8; a map not named is 1.0) and `wave_alive_share_by_map` (the share of the cap up at once, school 0.55, ballpark 0.85; a map not named uses `wave_alive_share`). Size alone did not harden the ballpark: its waves got longer but the room (`wave_alive_share` of a cap of 82) held the peak where it was, and wave 10, where the share reaches 1.0, was the only wave that ever downed the team. Seeds 3 to 8, wave lost in (won is 10+), one run per cell:

| Map (team) | Setting | 3 | 4 | 5 | 6 | 7 | 8 | Median |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| School (12) | scale 1.3, share 0.55 | 4 | 10 | 6 | 9 | 10 | 4 | 7.5 |
| Mall (14) | scale 1.15 | 8 | 10 | 9 | 8 | 5 | 8 | 8 |
| Camp (10) | scale 0.85 | 10 | 8 | 7 | 8 | 7 | 9 | 8 |
| Ballpark (16) | scale 1.8, share 0.85 | won | 10 | 3 | 9 | won | 8 | 9.5 |

The steps on the way (medians): school 8.5 at scale 1.15, 9 at 1.3, 9 at 1.45, 7.5 with the share; mall 9.5 at 1.0; camp 6.5 at 1.0; ballpark 10.5 at 1.4, 10 at 2.5, 9.5 with the share 0.85, 10.5 at share 1.0 (more room did not help: the cells are a hold cleared or lost in 3 to 4). **The ballpark is the map still off the band**: its hold is bimodal (cleared, or lost early to one bad post), and a single run per cell cannot tell 0.85 from 1.0. One seed moves a cell by six waves, so read the median only. The same unchanged camp measured 6 (the table above) and 8.5 (a later partial run).

**Ballpark retuned again (zz-bots-helpers-1).** With two helpers the ballpark was still above the band (median 9.5). Seeds 3 to 6, wave lost in (won is 10+), one run per cell; only the ballpark's two entries in `wave_scale_by_map` and `wave_alive_share_by_map` moved, so the other three maps' rows above stand:

| Map (team) | Setting | 3 | 4 | 5 | 6 | Median |
| --- | --- | --- | --- | --- | --- | --- |
| Ballpark (16) | scale 2.4, share 0.85 | won | 10 | | | 10 |
| Ballpark (16) | scale 3.6, share 1.0 | 9 | 9 | | | 9 |
| Ballpark (16) | **scale 5.0, share 1.0 (kept)** | 8 | 7 | 8 | not finished | 8 |

The ballpark's team of sixteen with two helpers needs a much bigger wave than the other maps before its middle waves hurt. Seeds 7 and 8 were not re-run (the build slot was shared); read the median, never a cell. `headless_survival`'s "the stand-ins kill what comes" now asks for more than 2 kills in 75 s, not more than 5: the camp's wave 1 is 10 zombies and the two answering stand-ins left it at 5.

## The server tick at 16 to 128 survivors (zz-scale-probe-1, 2026-10-19)

`tools/server_probe.sh` (one process per row, through `heavy`; `tools/server_probe.tscn` for one row; `tools/server_probe_table.py` makes the tables) runs the real server half on `zz_stadium` (the biggest survival map): `ZzGame`, a `DotNetManager` and `ZzNetBridge` with the socket replaced by a counter, N survivors each seated as a peer (own entity, own snapshot) and driven by the stand-in brain, the hold put at wave 10, and the commons topped up to `commons_cap(N)` (or a fixed `--commons`) until the window opens; the window is 12 s of play. Phases are laps around `ZzGame._step`'s own calls (kept in step with it, as `survival_long_run --profile` is) and around the manager's half of the tick; times are ms per tick, means over all ticks of the window, so `net snapshot` is the mean of ticks that send and ticks that do not (30 snapshots/s: every second tick at 64 Hz, every tick at 33 Hz).

**Read these as relative costs, not absolute.** The VM was shared (load 2 to 4), peers do not acknowledge snapshots (the no-ack host; a real client acks, which game-g2gfast's load probe found changes a snapshot's cost), and the engine step is the time spent awaiting one physics frame once every 16 ticks, which includes whatever else the machine was doing. dot-npc has no timer inside a path search, so pathing is derived: searches per tick (`DotNpcNavGraph.searches`) times the cost of one search measured on the same graph afterwards; it is part of `brains`, not additional.

| survivors | Hz | commons (cap) | budget | total mean | p50 | p95 | max | game logic | senses | brains | bodies | horde other | net pull | **net snapshot** | engine step | pathing (derived) | B/s per peer | peak MB |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 16 | 64 | 80 (82) | 15.6 | 19.8 | 23.5 | 33.0 | 41.5 | 3.3 | 1.1 | 2.4 | 0.7 | 0.5 | 0.5 | **11.4** | 0.6 | 0.2 | 36778 | 275 |
| 32 | 64 | 114 (114) | 15.6 | 44.7 | 68.3 | 77.7 | 86.3 | 7.5 | 1.2 | 2.5 | 0.9 | 1.0 | 0.8 | **30.9** | 0.7 | 0.6 | 52903 | 357 |
| 64 | 64 | 170 (178) | 15.6 | 146.6 | 199.6 | 297.8 | 414.4 | 15.6 | 4.6 | 8.3 | 1.9 | 2.1 | 1.7 | **112.5** | 4.0 | 0.7 | 84944 | 671 |
| 100 | 64 | 215 (250) | 15.6 | 243.2 | 372.9 | 490.7 | 629.4 | 24.9 | 4.1 | 10.1 | 2.5 | 3.6 | 2.4 | **195.7** | 17.2 | 1.6 | 84634 | 1118 |
| 128 | 64 | 274 (306) | 15.6 | 369.7 | 497.8 | 765.6 | 969.0 | 35.2 | 5.7 | 15.1 | 3.2 | 5.2 | 3.2 | **302.1** | 25.6 | 1.5 | 79807 | 1636 |
| 16 | 33 | 79 (82) | 30.3 | 33.2 | 33.2 | 37.2 | 55.2 | 3.8 | 1.1 | 3.0 | 0.9 | 0.6 | 0.6 | **23.3** | 0.8 | 0.3 | 33990 | 269 |
| 32 | 33 | 113 (114) | 30.3 | 97.9 | 88.1 | 170.8 | 310.7 | 8.6 | 1.4 | 3.4 | 1.3 | 1.4 | 1.2 | **80.7** | 1.0 | 1.2 | 49039 | 343 |
| 64 | 33 | 157 (178) | 30.3 | 265.8 | 249.3 | 379.0 | 516.9 | 17.7 | 4.5 | 9.6 | 2.1 | 2.4 | 1.8 | **227.7** | 8.7 | 1.5 | 81265 | 663 |
| 100 | 33 | 238 (250) | 30.3 | 474.4 | 435.5 | 699.5 | 881.0 | 28.5 | 4.7 | 14.9 | 2.9 | 4.2 | 2.6 | **416.6** | 26.5 | 1.7 | 74339 | 1069 |
| 128 | 33 | 253 (306) | 30.3 | 592.1 | 591.3 | 667.6 | 716.0 | 35.9 | 5.3 | 18.6 | 3.5 | 5.0 | 3.0 | **520.8** | 43.7 | 2.3 | 75863 | 1610 |
| 64 | 64 | 236 (fixed 250) | 15.6 | 151.4 | 221.4 | 282.9 | 320.5 | 15.9 | 5.2 | 12.1 | 2.6 | 2.4 | 1.9 | **111.4** | 6.7 | 0.9 | 80382 | 770 |
| 64 | 64 | 148 (fixed 150) | 15.6 | 125.6 | 191.2 | 238.8 | 256.4 | 14.2 | 3.0 | 6.4 | 1.6 | 1.8 | 1.4 | **97.2** | 3.9 | 0.6 | 86143 | 652 |
| 128 | 64 | 232 (fixed 250) | 15.6 | 313.4 | 458.2 | 679.7 | 880.0 | 34.1 | 5.5 | 11.7 | 2.6 | 4.2 | 2.8 | **252.4** | 16.2 | 1.6 | 77271 | 1538 |
| 128 | 64 | 147 (fixed 150) | 15.6 | 258.0 | 400.8 | 497.3 | 527.4 | 31.8 | 3.8 | 5.6 | 1.5 | 3.1 | 2.1 | **210.0** | 4.4 | 0.9 | 79690 | 1272 |

Every row is over its budget, the 16-survivor row too (19.8 ms against 15.6; the 10 to 11 ms measured above was `headless_survival` without the net half, where the snapshot is 11 of these 20). Memory fits: 1.6 GB at 128 survivors, so nothing had to be stopped for it; the cost is time (a 128 row takes about 15 minutes of wall clock for 12 s of play).

**The three costs at 128 survivors and 64 Hz** (of 370 ms a tick): (1) **snapshot build and send, 302 ms (82 %)**, growing with the square of the team (11, 31, 112, 196, 302 ms at 16, 32, 64, 100, 128): every peer is sent every relevant entity, and the horde's 274 zombies are always relevant (`zz_npc_net`); `net_history` is nothing (0.01), `net_pull` 3 ms. (2) **Game logic, 35 ms**: the stand-ins' decisions (`bots.drive`), 128 survivors' controllers and hands, weapons, combat, the world; linear in the team. (3) **Zombie brains, 15 ms** (senses another 6, bodies' `move_and_slide` 3): linear in the horde; path searches are only 1.5 ms of it (9 a tick at 160 us), so the pathing is not what costs. The engine's physics step comes fourth (26 ms, noisy). The fixed-crowd rows say the same from the other side: at 128 survivors going from 150 to 250 commons adds 6 ms of brains and 42 ms of snapshot; the team, not the horde, sets the tick. The first lever for a bigger team is therefore the snapshot (interest filtering for the zombies, a lower snapshot rate, a measured acking host), the second the stand-ins' logic.

### Relevance by distance (zz-scale-levers-1, the first lever, 2026-10-19)

Zombies are no longer all `always_relevant`. `ZzNetBridge.make_interest` is a `DotNetInterestDistance` (not the grid: it has one radius, and a special wants a wider one than a common; the distance rule has one per tag and its query over a few hundred entities is cached a quarter of a second per peer): commons 80 m (`TAG_COMMON`), specials and the sleeper 260 m (`TAG_SPECIAL`), the brute always, players always (a teammate's outline, health and position are the HUD), everything else 200 m. A zombie that leaves a peer's radius is still sent for three seconds (`interest_linger_sec`, the time half of hysteresis; dot-net's strategies have one radius each). A client hides a zombie mirror 12 m past its kind's radius from its own survivor, because the server has stopped telling it where the body is and it would otherwise stand frozen. `headless_net` has an armed section (a far boss still tracked, a far common not sent, a teammate tracked).

| survivors | Hz | commons | total mean / p95 | net snapshot (mean) | B/s per peer | before: net snapshot | before: B/s per peer |
|---|---|---|---|---|---|---|---|
| 16 | 64 | 80 | 34.8 / 91.3 | 20.4 | 33332 | 11.4 | 36778 |
| 32 | 64 | 114 | 59.4 / 160.5 | 42.1 | 47943 | 30.9 | 52903 |
| 64 | 64 | 170 | 239.8 / 674.6 | 191.1 | 84201 | 112.5 | 84944 |
| 100 | 64 | 215 | 269.7 / 528.9 | 222.9 | 94366 | 195.7 | 84634 |

**Read this as: the lever does almost nothing on this map, and the times above are not comparable to the old ones.** The "after" rows ran with the VM at load 8 (the old ones at 2 to 4): the whole tick, game logic included, is 1.5 to 2 times slower, so milliseconds say nothing; bytes per peer do not depend on load. The reason is geometry: `zz_stadium` is 170 by 175 m, and the survivors are spread over all of it with the horde on them, so an 80 m radius leaves a peer most of the horde. Counted at the end of the 64 row (`relevant_per_peer` in the RESULT line): 239 entities in the world, **191 sent to each peer**, of which 64 are the survivors themselves (always relevant, a third of what a peer is sent) and 127 of 175 zombies. Relevance pays on a map larger than its radius with the team spread out, which no map here is yet; at 100 survivors on this one it does not shrink the snapshot enough to matter. What would: the per-entity cost of a snapshot (the same 191 entities cost 190 ms across 64 peers, 1 ms each), which is dot-net's threading (net-snapshot-threads-1) and the snapshot rate; and, for the 64 survivors in every peer's set, a cheaper description of a faraway teammate than a full entity (a low-rate roster channel, then players could be tagged by distance too). Not done: spectators see a teammate's surroundings only if they are near their own body, so a downed survivor watching a friend across a large map would see no zombies there.


## Stuck movers by map

`headless_nav --only=stuck` plays each shipped map for 150 simulated seconds with a team of stand-ins against its horde, and `tools/stuck_meter.gd` counts the seconds a mover with a goal stayed within 0.75 m for 4 s (a zombie fighting, bashing or with no path does not count). Percent of the seconds a mover of that kind had a goal; one run per map each side, and a kind with a few dozen goal seconds swings by tens of points between two runs of the same code (a single wedged stand-in), so read the commons columns and the large moves. Specials have no goal time in 150 s and are unmeasured.

Three changes: props from 0.3 m are cut from the graph (was 0.5: a 0.41 m pallet wedged every zombie that met its corner), a mover that hops twice without freeing itself is nudged sideways (`game/zz_unstick.gd`), and the loot rate. A fourth, dropping importer links that cross a wall, was tried and removed: it fixed atix and broke ground connectivity on four maps (`headless_maps`), because those links are the only connection the document has.

| map | stand-in before | after | common before | after | worst stretch before (s) | after |
| --- | --- | --- | --- | --- | --- | --- |
| zz_blackout_2 | 0.0% | 0.0% | 3.0% | 6.8% | 18 | 8 |
| zz_blackout_3 | 0.0% | 15.6% | 2.8% | 3.7% | 4 | 8 |
| zz_high_school | 22.9% | 9.6% | 3.5% | 3.2% | 19 | 10 |
| zz_lot | 40.5% | 2.7% | 0.0% | 0.0% | 23 | 4 |
| zz_mall | 17.5% | 49.0% | 1.8% | 0.0% | 10 | 28 |
| zz_stadium | 14.7% | 0.0% | 9.9% | 0.3% | 60 | 4 |
| zs_ravenstreet | 6.5% | 25.1% | 0.0% | 0.0% | 7 | 25 |
| zm_atix_helicopter | 56.5% | 58.5% | 4.4% | 15.2% | 26 | 27 |
| zm_house_outbreak | 0.0% | 0.0% | 43.4% | 1.5% | 68 | 8 |
| zm_officeattack | 0.0% | 0.0% | 11.6% | 7.6% | 14 | 9 |
| ze_blackmesa_escape | 10.8% | 10.8% | 29.6% | 0.0% | 38 | 4 |
| ze_death_star_escape | 0.0% | 0.0% | 17.9% | 0.5% | 42 | 4 |
| ze_nuke_beta | 50.1% | 50.0% | 4.7% | 10.6% | 20 | 42 |

The other ten maps are at or under 13% for both kinds before and after. Open: the atix stand-ins walk into a window sill the importer linked across (zombie-zone-maps `import_bsp.py`), the nuke stand-in on a sill doorway, and zm_antarctic_hospital (unshipped, imported to a scratch directory only) stands commons at 27% against a window counter with a pillar over it.

Reach after the steep-edge rule, floor-piercing link cut and stuck rescue (`special_reach --all`, 30 maps, 148 origins): commons path 132, reached 136 (was 88 of 119, 74%; now 92%), brute path 137, reached 116. `zm_roy_the_ship` commons 2 of 5 reached (was 0): its drop links were read upward (`zz_nav_steep`, default 1.2 m, walks them downhill only). The importer (`zombie-zone-maps/tools/import_bsp.py`, `cut_blocked`) now cuts doc links that pierce a floor slab, as `ZzNpcs._link_through_floor` does at load; ze_nuke_beta and ze_boat_escape are left uncut, because the cut disconnects their routes. Open: `zs_krusty_krab_large` (a drop lands in a pit at 3.9, -15.8, 6.5 with no nav points), `zs_slugde` (no links, 4 components, 5 of 8 wave hints in one island), `zm_roy_highway` and `zs_lens` (island hints; 42 posts need the unwired ladders). Ladders are not exempt from `zz_nav_steep` yet.

## Sprint and stamina

Hold Shift to sprint (slow walk is Alt). The logic is dot-player-controller's (`DotFpsMotor._tick_stamina`, state in `DotFpsState.stamina`), so it is server-simulated and predicted by the client like the rest of the movement; ZZ only sets defaults (`ZzConfig`: `sprint_enabled`, `sprint_speed_scale` 1.22, `stamina_enabled`, `stamina_drain` 0.2/s, `stamina_recover` 0.15/s, `stamina_resume_at` 0.3, `stamina_exhaust_delay` 1.5 s, `sprint_load_speed`, `sprint_load_drain`) and draws the bar over the health plate. Running out sets exhausted: sprint refuses until stamina is back at `stamina_resume_at`, and refill waits `stamina_exhaust_delay`. The carried share of the weight limit (`motor.load_fraction`, set from the carry rules on the server and from the CARRY event on a client) cuts the sprint bonus by `load x sprint_load_speed` and raises the drain by `load x sprint_load_drain`; 0 turns either off. The addon-side cvars are `sv_sprint`, `sv_sprintspeed`, `sv_stamina*`, `sv_sprint_loadspeed`, `sv_sprint_loaddrain`, `sv_sprint_noaim` in `DotFpsTunables`.

`tools/special_reach.tscn` (`-- --all|--map=ID [--origins=3] [--seconds=30] [--static] [--ai]`, through `heavy`) places the common walker (the control) and each special at wave origins and reports per map origins with a path / origins reached within 4 m / median seconds, and `!n` for misses that had time to walk the path and stood still the last 8 s. Default it drives the shared steering straight at the nearest survivor (the kinds' ground limits); `--ai` lets each kind's tactics run. Driven, all 30 survival maps: every special matches the common (82-88 of 119 origins; the misses are shared map snags: zm_lila_panic, zm_roy_the_ship, zs_krusty_krab_large, zz_high_school, zz_mall, zz_relief_camp, zz_stadium reach nothing) except the brute, which is worse (72 of 119; chaos_city 0/4, officeattack 0/4, 16chambres 1/4 where commons arrive). With `--ai` specials park in `approach` 20 to 60 m short on a clumped team (hidden-spot search, `ready_to_strike`), which is tactics, not ground.

special_reach also takes `--kinds=a,b` (the common always runs), `--trace` (position, state, path every 2 s) and `--edges=x,y,z` (graph edges and ray hits around a place). Barricades are opened by default (`--held` keeps them): zz_high_school, zz_mall, zz_relief_camp and zz_stadium were barricades the probe never broke, not nav snags. Real causes found and fixed: the brute's NARROW test used the common's capsule (now its own radius and `fit_height` 2.1, with a relaxed retry in `ZzNavGraph.find_path`), imported `nav.links` piercing floor slabs (zm_lila_panic; rejected by `_link_through_floor`, converter `tools/nav_emulate.py` still emits them), and solid-prop head cuts measured from sea level instead of the floor under them. Still open: zm_roy_the_ship and zs_krusty_krab_large commons stop at geometry the graph does not mark, and the `--ai` approach stall.
