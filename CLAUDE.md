# game-zombie-zone

A co-operative zombie shooter: a team of survivors crosses an **exodus** map from shelter to shelter, or a team of a dozen or more holds a big **survival** map (ten escalating waves by default; days and nights or a clock by `zz_survival`) behind barricades it mends, against a directed horde, eleven kinds of special infected with one trick each, and boxes the zombies drop that do something random. Hardcore by default: friendly fire on, three downs and you are dead, a horde that circles you rather than queueing.

Read the family-wide conventions in [`../../CLAUDE.md`](../../CLAUDE.md) first, and each addon's own `CLAUDE.md` before working in it (dot-npc, dot-npc-ai and dot-npc-ai-director most of all). This file is what the game decides now; the reasoning is in `docs/`. The maps are in `maps/`, a link to [zombie-zone-maps](../zombie-zone-maps), written by its `tools/build_maps.py`; `maps/README.md` there is the format. The genre the brief came from is never named in a public file (family rule).

| Read | Before |
| --- | --- |
| [docs/design.md](docs/design.md) | Changing the netcode split, the zombies' ground, the director, downs, boxes, weapon packs, stand-ins, the HUD, cameras, the look, delivery or the vote |
| [docs/survival.md](docs/survival.md) | Touching a survival map, a wave, a barricade, the team size, the crowd's cost, or the numbers (the long-run measurements are there) |
| [docs/zombies.md](docs/zombies.md) | The zombie models, their animation, what a special wears, a death |
| [docs/history.md](docs/history.md) | Believing a suite: the bugs found by running |

## Layout

```
game/
  zz_config.gd       every rule a map is played under: difficulty, downs, horde, specials, boxes, bots, survival
  zz_map_doc.gd      what a map IS: boxes (looks), props, lights, spawns, safe areas, route, nav, items, objectives (props)
  zz_map.gd          a document built: solid boxes, gates and barricades as separate bodies, props, areas, the sky
  zz_fixtures.gd     what objectives and gates look like: chain-link, a padlock and chain, a lever, a radio
  zz_catalogue.gd    every map the server has, and the built-in practice street
  zz_npcs.gd         the zombie catalogue (twelve kinds), and the nav graph a map's document gives
  zz_horde.gd        the horde: spawner, director, senses, squads, sounds; mobs, specials, brutes, sleepers, waves
  zz_pins.gd zz_hazards.gd zz_loot.gd zz_boxes.gd zz_weapons.gd   being held; acid, fire, throws; loot; boxes; tiers
  zz_survival.gd     a survival map held: dot-npc-ai-director's DotNpcDirectorWaves, the breather, twists, caches
  zz_bots.gd         stand-in survivors (posts, mending and restocking on a survival map)
  zz_controller.gd zz_player.gd   DotFpsController with the game's modifiers; one survivor
  zz_game.gd         the simulation: map flow, combat, hands (use/heal/pills/shove), downs, objectives, barricades
  zz_hud.gd zz_world_view.gd zz_client.gd zz_audio.gd   what a person sees and hears
  zz_module.gd       the DotGameModule: cvars, console and admin commands, stand-ins
  net/               the codec (NPC, PIN, LOOT, BOX, HAZARD, BLAST, ROUND...), behaviours, the bridge
npcs/                the zombie body, its view (the animated models), one brain script per kind (by path)
assets/zombies/      the animated bodies (tools/build_zombie_models.py) and the kit's atlases
boxes/boxes.json     the box types and every outcome; an owner edits it
props/               kits.json, catalogue.json, pieces.json (tools/measure_props.gd writes the last two)
examples/            headless_run (31 sections), headless_maps, headless_net (15), headless_weapons, dedicated, headless_survival
tools/               shot.sh (render a view), camera_check.sh, survival_long_run.tscn (a whole hold, measured),
                     zombie_rack.gd, zombie_palette.gd, build_zombie_models.py, audio_probe
```

## Rules

**The split and the wire** ([design](docs/design.md#decision-1-the-zombies-are-the-servers-and-a-client-draws-them))
- Zombies are the server's, never predicted, always relevant; a client interpolates them and is told a death (NPC_GONE) so a body falls.
- Everything that changes how a survivor moves is a `ZzController` modifier, never a velocity written on one end.
- Every `ZzEvents.Kind` fits `ZzEvent.KIND_BITS` (6 bits); `headless_net` checks it. [history](docs/history.md)
- No `class_name` in `game/` or `npcs/` (a mounted pack cannot register one); brains are named by path.

**The ground and the horde** ([design](docs/design.md#decision-2-the-zombies-ground-is-the-maps-own-floor-plan))
- `nav.floors` comes from the map; every solid box, prop over half a metre and shut gate is cut out; opening a gate rebuilds the graph.
- A mob spawns only where it can reach somebody, and never in a safe room.
- Only `attackers_per_survivor` take an attack slot; the rest ring. Specials wait for a moment (`ready_to_strike`).
- A brain seeds from `npc.seed`, never `npc.instance_id`; suites wait for a zombie's state, never time its seeded choice. [history](docs/history.md)
- A brain checks its body still exists after its kind's decision (a bloater that bursts is gone by then).
- Zombies and stand-ins ask `ZzHorde.zombies_near` (a grid built once a tick), never the spawner's `npcs_near`.
- A wave's speed is `ZzZombieBody.speed_scale`, never written onto the wish (it compounded between thoughts). [history](docs/history.md)
- A zombie below `kill_y` is removed and a wave's owed again (`ZzHorde._fell_out`, which records where it left the floor). [history](docs/history.md)
- A special breaks off hurt only when hurt further than at its last retreat. [survival](docs/survival.md#ten-waves-played-zz-survival-long-run-1-2026-10-12)

**Survivors, downs, boxes, weapons** ([design](docs/design.md#decision-4-down-is-not-dead-and-borrowed-health-is-inside-the-health))
- Borrowed health lives inside `DotHealth.health` with `temp_health` saying how much; a hit takes it first.
- A box verb unknown to `ZzBoxes` refuses the whole file with a reason; one `_do_<verb>` per verb; lasting effects stack.
- A second weapon pack is a list (`ZzWeapons.use_packs`); tiers are by tag; everything a weapon throws goes through `ZzGame._throw`.
- Your gun is two rigs: the world's (`ZzPlayer.weapons`) and the drawn one (`view_rig`, what the HUD counts); offline buttons go through `command_stamp`. [history](docs/history.md)
- A shot starting inside a survivor skips them (`zz_trace.gd`); stand-ins hold fire for a friend's hitboxes in the line.
- Stand-ins aim and shoot through dot-bot's `DotBotAim`; never set `command.yaw` straight onto a target. They shoot the head when only the head shows over boards.
- H is help and M is the map list: nothing in `ZzBindings` defaults to either (the medkit is G, the shove F, and an old settings file follows them through `keys.renamed`); `headless_run` and `dedicated` check it.
- A cvar and a command never share a name (the cvar is `zz_box_drops`, the command `zz_boxes`).

**Survival** ([survival](docs/survival.md))
- The hold is `DotNpcDirectorWaves`, never the director's stress cycle; a wave is released by `take()` within `commons_cap`, refused spawns are owed again, it ends cleared or on `overtime`.
- A wave comes from the map's `zombie_spawns` first (`ZzHorde._wave_origin`); a release leaves room for what is queued (`pending_commons`).
- A survival map's wanderers take at most a fifth of the cap and are sent in as each wave begins. [survival](docs/survival.md#ten-waves-played-zz-survival-long-run-1-2026-10-12)
- A barricade's boxes are `"nav": false` and `nav_for` skips them: the horde paths INTO a barricade to bash it; `headless_maps` checks both faces are on the graph.
- Nobody mends a barricade torn at in the last `ZzGame.MEND_LOCKOUT` (1.5 s); without it no wave was ever cleared. [survival](docs/survival.md#barricades)
- Barricade state goes to clients in sixteenths (BARRICADE) and at every round start; the hold as SURVIVAL every clock and on every stage change; `headless_net` follows both through the bridge.
- `survivors` in a map raises the stand-ins to that team; unsaid is 0, never 4. Commons alive: 6 per survivor for eight, 2 past them.
- Tune waves with `tools/survival_long_run.tscn` (whole holds, `--from`, `--profile`); `headless_survival` fails a big map whose wave-1 tick is over 15.6 ms.
- Suites read a map's result from `round_over`: with no intermission the next round has cleared `_decided`. [history](docs/history.md)

**The zombies' look** ([zombies](docs/zombies.md))
- After rebuilding a GLB run `godot --headless --path . --import` before anything renders it. [history](docs/history.md)
- The palette shader samples like a StandardMaterial3D (`source_color`); a survivor body plays zombie clips through `_retarget`; an attachment's offset is in the body's axes from the joint.
- `ZzZombieBody.Anim` is replicated in 5 bits: append, never insert, stop at 31. `WEARS` colours come from `tools/zombie_palette.gd`.
- Survivors are dot-player-char's `DotHumanoidFigure` (`ZzFigure`, the same kit and rig); a killed zombie ragdolls by its bones (`ZzWorldView.ragdolls`, capped per machine, off under `sv_ragdoll 0`), which needs dot-player-char API level 3.

**The HUD and the screen** ([design](docs/design.md#the-hud-dot-uis-glance-pieces))
- Glance pieces are dot-ui's (vitals, ammo, strip, key hints, hit marker, damage numbers); naming them needs a shell with dot-ui API level 4, which `headless_run` checks.
- The HUD follows the menu's theme (`ZzHud.follow_menu`, dot-menu's `follow_hud` by name); `piece_theme()` is accent only (amber, health green); Labels set no colour of their own except accent lines.
- Every character the game writes is in the HUD's font (`headless_run` scans `game/` and `npcs/`); bars are drawn, never block characters. [design](docs/design.md#what-the-first-play-test-changed-2026-10-11)
- Feed lines go through `ZzClient.feed_line`: "You are down", never "You is down".
- A hit is drawn only from the server's confirmation (`ZzGame.hit_landed`); the health number is real health, borrowed is the white length.
- The health plate ends 206 px off the bottom, above a full chat log (202); `headless_run` checks the arithmetic.
- Between a decided map and the next the strip counts down (`next_round_seconds`, sent in ROUND).
- `mp_solidplayers` and `mp_forceview` are REPLICATED and followed through the link; third-person and spectate cameras stop against the world. [design](docs/design.md#cameras-and-bodies)
- A night map draws its own sky (`ZzMap._dress_night_sky`: stars, a moon where the moonlight comes from); the fog and fill keep the map's numbers. Night maps stay night; render both renderers before changing a light number.
- A gate may `look` like chain-link and a `use` objective may be a `prop` (padlock on its gate, lever, radio) from `zz_fixtures.gd`; pictures only, the box still collides.

**Delivery** ([design](docs/design.md#delivery-and-the-map-vote))
- `project.godot` carries no comments (the editor drops them); gravity is `ZzConfig.gravity` on the world's own space; the renderer is `gl_compatibility`; texture imports keep `detect_3d/compress_to=0`.
- The maps pack is named by the server owner, never by `game.yml`; `ZzModule` adds every mount's `maps/` at load and after `zz_reload`.
- Under MANUAL `ZzVote` opens a passed rock-the-vote itself, and `_game_load` refreshes the map list after the delivered maps; the match answers `round_in_progress_fn` by name.

## Validating

```bash
./game.sh test                                          # parse, then every suite
python3 ../zombie-zone-maps/tools/build_maps.py --check
godot --headless --path . res://tools/survival_long_run.tscn -- --map=zz_high_school [--from=7] [--profile] [--watch=30 --detail]
xvfb-run -a godot --path . res://tools/audio_probe.tscn
tools/shot.sh --view=overview --zz-map-ids=zz_blackout_1
tools/shot.sh --view=room --alone --zz-map-ids=zz_blackout_1 --at=16.6,1.6,65.4 --look=18,1.1,66   # the fence and its padlock
tools/shot.sh --view=room --zz-map-ids=zz_blackout_1 --at=0,1.7,20 --look=0,9,50                     # the night sky
tools/shot.sh --view=wave --zz-map-ids=zz_high_school --zz-survival-warmup-seconds=3 --seconds=60 --at=-3,0.05,11 --look=-3,1,16
tools/shot.sh --view=hit --spawn=common:6               # team bars, marker, number, borrowed health, a hold-out clock
tools/camera_check.sh --render
tools/shot.sh --view=third --spawn=brute:1,leaper:1
tools/shot.sh --view=pinned --pin=ride --pin-me
xvfb-run -a godot --path . --script tools/zombie_rack.gd -- --set=horde --at=5    # also --kinds=..., --set=commons, --set=deaths
tools/shot.sh --view=weapons --weapons=all --out=res://screenshots/weapons
```

Without `maps/` linked in (CI clones this repository alone) `headless_maps` checks the practice street only, and says so.

## Still to do

1. **Put it live.** The client shell needs dot-ui API level 4. Tag zee-dot-weapons (`add_source`) and zed, dot-npc (native search, `warm()`, `go_rough`), dot-npc-ai (the shared surround, rough corners) and dot-npc-ai-director (API level 2, `DotNpcDirectorWaves`) and anything else changed, add `content/zombiezone/` and a client example to dot-server-deploy, rebuild the shell; then the game, and the maps pack after it (its Blackout maps say `exodus`, which an older game refuses).
2. **Bile that turns the horde on itself**: a splashed common is drawn (FLAG_BILED) but no brain targets another zombie yet.
3. **More box outcomes**, written by the owner, toward the hundred.
4. **Retune the waves from continuous holds**: they are harder on every map since the cap went to the waves (see [survival](docs/survival.md#ten-waves-played-zz-survival-long-run-1-2026-10-12)).
5. **Play it with people**, and set normal's numbers from that.
