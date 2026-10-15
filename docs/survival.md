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
