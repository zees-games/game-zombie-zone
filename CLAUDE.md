# game-zombie-zone

A co-operative zombie shooter: survivors cross an **exodus** map from shelter to shelter, or a dozen or more hold a big **survival** map (ten waves by default; `zz_survival`) behind barricades they mend, against a directed horde, eleven specials with one trick each, and boxes the zombies drop. Hardcore by default: friendly fire on, three downs and you are dead.

Read the family [`../../CLAUDE.md`](../../CLAUDE.md) first, and each addon's `CLAUDE.md` before working in it (dot-npc, dot-npc-ai, dot-npc-ai-director most of all). This file is the rules now; the reasoning is in `docs/`. `maps/` links [zombie-zone-maps](../zombie-zone-maps) (its `tools/build_maps.py`, `maps/README.md` the format). The genre the brief came from is never named in a public file.

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
  zz_mechanics.gd    a drawn world's lifts, doors, buttons, trigger volumes and links (dot-map's DotMapEntities), run by the server
  zz_fixtures.gd     what objectives and gates look like: chain-link, a padlock and chain, a lever, a radio
  zz_catalogue.gd    every map the server has, and the built-in practice street
  zz_npcs.gd         the zombie catalogue (twelve kinds), and the nav graph a map's document gives
  zz_npc_profiles.gd the twelve kinds as dot-npc profiles (cfg/game/game-zombie-zone/npc/<id>.yml, written by tools/export_npc_profiles.gd from the code table; a key overrides only when it differs from the shipped value, so cvars and difficulty still reach an unedited kind; `health` is unscaled, a brute's is its base; the sleeper's cost stays in code)
  zz_horde.gd        the horde: spawner, director, senses, squads, sounds; mobs, specials, brutes, sleepers, waves
  zz_turrets.gd (the Turret Box's sentries: placement, targeting and ammo are dot-combat's `DotSentry`, the box rule and tuning are here) zz_pins.gd zz_hazards.gd zz_loot.gd zz_boxes.gd zz_box_effect.gd zz_box_instakill.gd zz_weapons.gd   being held; acid, fire, throws; loot; boxes; tiers
  zz_survival.gd     a survival map held: dot-npc-ai-director's DotNpcDirectorWaves, the breather, twists, caches
  zz_bots.gd         stand-in survivors (posts, mending and restocking on a survival map)
  zz_controller.gd zz_player.gd   DotFpsController with the game's modifiers; one survivor
  zz_game.gd         the simulation: map flow, combat, hands (use/heal/pills/shove), downs, objectives, barricades
  zz_hud.gd zz_world_view.gd zz_client.gd zz_audio.gd zz_figure.gd   what a person sees and hears (survivors: dot-player-char people)
  zz_module.gd       the DotGameModule: cvars, console and admin commands, stand-ins
  net/               the codec (NPC, PIN, LOOT, BOX, HAZARD, BLAST, ROUND...), behaviours, the bridge
npcs/                the zombie body, its view (the animated models), one brain script per kind (by path)
assets/zombies/      the animated bodies (tools/build_zombie_models.py; the worker is art-src/zombie_worker.py) and the atlases
assets/turret/       the sentry (art-src/turret.py, Blender on the GPU box via ../gpu.sh)
boxes/boxes.json     the box types and every outcome; an owner edits it
props/               kits.json, catalogue.json, pieces.json (tools/measure_props.gd writes the last two)
examples/            headless_packs (optional packs, a fixture provider), headless_run (40 sections), headless_maps (also reads every drawn world), headless_mechanics, headless_net (18), headless_weapons, dedicated, headless_survival, headless_nav (15 sections, 56 checks; the last three hold blackout_2, lot and high_school to a stuck-time band), headless_workshop (subscribed map packs: listed, chosen in solo, built from their document; online none)
tools/               nav_probe, nav_render (debug top-down plus a frame of holders), shot.sh (render a view), camera_check.sh, survival_long_run.tscn (a whole hold, measured), server_probe.sh (the server tick by phase at 16 to 128 survivors),
                     zombie_rack.gd, zombie_palette.gd, build_zombie_models.py, audio_probe
```

## Rules

**The split and the wire** ([design](docs/design.md#decision-1-the-zombies-are-the-servers-and-a-client-draws-them))
- **Sound follows the map document** (box `mat` → footsteps by surface, `ceiling`/`roof` boxes → indoor zones, `ZzAudio.MAP_SOUND` beds); levels by dot-audio's `loudness.sh`, −17 LUFS. [design](docs/design.md#sound)
- Zombies are the server's, never predicted, relevant by distance and kind (the brute always; `ZzNetBridge.make_interest`); a client interpolates them and is told a death (NPC_GONE) so a body falls.
- **A READY before the player is seated is kept** (`_ready_unseated`) and answered by `add_player`; `headless_net` sends it first (armed). [history](docs/history.md)
- Everything that changes how a survivor moves is a `ZzController` modifier, never a velocity written on one end.
- Every `ZzEvents.Kind` fits `ZzEvent.KIND_BITS` (6 bits), and `ZzEvent.MAX_BODY` holds the largest MAP (`ZzEvents.MAP_BYTES`): a longer body reads as empty, silently; `headless_net` checks both.
- Map toys are loose only (dot-props; walked through, pushed by survivors, shot along the ray without stopping the shot); a client registers every toy mirror on TOYS before its map is built. [design](docs/design.md#toys-loose-ones-only)
- No `class_name` in `game/` or `npcs/` (a mounted pack cannot register one); brains are named by path.

**The ground and the horde** ([design](docs/design.md#decision-2-the-zombies-ground-is-the-maps-own-floor-plan))
- `nav.floors` comes from the map; every solid box, prop over 0.3 m (a pallet wedges a mover well below half a metre) and shut gate is cut out, and the importer's links are NOT filtered: some run through window sills and walls (zm_atix_helicopter), but dropping them disconnects the ground on four maps (headless_maps) because they are the only connection the document has, so the fix is in the importer; opening a gate rebuilds the graph. A mover that hops twice without freeing itself is nudged sideways (`game/zz_unstick.gd`). `tools/stuck_meter.gd` counts seconds a mover with a goal stays within 0.75 m for 4 s, by kind (stand-in, common, special): `headless_nav --only=stuck[:map]` prints it per map (a stand-in within a metre of a mate is queueing, counted apart from the ratio but still in the longest-stretch band; runs differ, so a map's ratio is judged over several), `survival_long_run --watch` ends with it.
- **Every map is walled in**: `ZzMap._build_boundary` puts four invisible walls on their own `boundary` layer (survivors and zombies stop at it; the nav bake and notes never see it: as world boxes they stretched the bake over the void and the annotator found no chokes) `BOUNDARY_MARGIN` (8 m) outside `playable_region()` (nav floors, spawns, route, areas, objectives), from under the kill height up, so a converted map's miles of terrain cannot be walked out onto; `headless_maps` rays out from a spawn on every side.
- A mob spawns only where it can reach somebody, and never in a safe room.
- Only `attackers_per_survivor` take an attack slot; the rest ring. Specials wait for a moment (`ready_to_strike`).
- A brain seeds from `npc.seed`, never `npc.instance_id`; suites wait for a zombie's state, never time its seeded choice. [history](docs/history.md)
- A brain checks its body still exists after its kind's decision (a bloater that bursts is gone by then).
- Zombies and stand-ins ask `ZzHorde.zombies_near` (a grid built once a tick), never the spawner's `npcs_near`.
- A wave's speed is `ZzZombieBody.speed_scale`, never written onto the wish (it compounded between thoughts). [history](docs/history.md)
- A zombie below `kill_y` is removed and a wave's owed again (`ZzHorde._fell_out`, which records where it left the floor). [history](docs/history.md)
- A ground slab collides `ZzMap.GROUND_DEPTH` deeper than drawn, a prop's flat floor plates are not collided, a leap ends after `LEAP_LONGEST` ticks and a fall is capped at `FALL_FASTEST`: each was a way through the floor. [history](docs/history.md)
- A special breaks off hurt only when hurt further than at its last retreat. [survival](docs/survival.md#ten-waves-played-zz-survival-long-run-1-2026-10-12)

**Survivors, downs, boxes, weapons** ([design](docs/design.md#decision-4-down-is-not-dead-and-borrowed-health-is-inside-the-health))
- Borrowed health lives inside `DotHealth.health` with `temp_health` saying how much; a hit takes it first.
- A downed survivor crawls at `zz_down_crawl_speed` (REPLICATED, `ZzCrawlRules`, 0 stays put) through `ZzController.set_crawl_speed`, never a velocity. Boxes default to a 1.0 s deploy (`box_deploy_seconds`, 0.5 to 15) and `box_labels` off: the opening is the surprise. Speed boxes are `ZzBoxSpeed` (`move_speed`, `crawl_speed`); `tools/shot.sh --view=crawl` / `crawl_third` render a downed crawl.
- **Water** is the map document's `water` list (`{at, size, tint?}`, the top face is the surface; the importer writes it from CONTENTS_WATER brushes with a floor in reach, `zombie-zone-maps/tools/import_bsp.py` `water_volumes`). `ZzMap.water_boxes` reaches every survivor as boxes on both ends through `ZzPlayer.set_water` and dot-player-controller's `DotFpsSwimMode` (`controller.extra_modes`, updated from `simulated`, replays included), never an Area3D. Wading is the `ZzController.WADING` modifier (the motor's 32 modifier slots are now all used: the next one needs a slot freed first), air and drowning are `ZzPlayer.breathe` and `ZzGame._advance_water` (server hurts, any end counts its own air for the bar), zombies are slowed by `ZzGame.water_pace_at` (they wade the bed, they do not swim). Every number is a `zz_water*` cvar in `ZzWaterRules` (`zz_water`, `_wade_scale`, `_swim_speed` REPLICATED). The surface is `zz_water.gdshader` (procedural, no texture, so no licence; animated sine normals, fresnel, glints, foam lip, seen from both sides), the murk and muffle are `ZzMap.set_underwater` and `ZzClient._present_water`. `tools/shot.sh --view=survivor --at=x,y,z` puts the eyes under; `--view=room` above (give it a short `--seconds`, a free camera's survivor falls in).
- A box verb unknown to `ZzBoxes` refuses the whole file with a reason; one `_do_<verb>` per verb; lasting effects stack.
- **Optional packs** (`spawn_provider.gd` under `res://addons`, `game/zz_packs.gd`) are scanned at start and duck-typed: never name a pack's class in `game/`. Weapons join through zee's `add_source`, monsters through `ZzNpcs._pack_defs`; tuning is `cfg/addons/zombie_zone/*.yml`. [design](docs/design.md#decision-7-optional-packs-are-found-not-linked-in)
- A second weapon pack is a list (`ZzWeapons.use_packs`); tiers are by tag; everything a weapon throws goes through `ZzGame._throw`.
- Your gun is two rigs: the world's (`ZzPlayer.weapons`) and the drawn one (`view_rig`, what the HUD counts); offline buttons go through `command_stamp`. [history](docs/history.md)
- A shot starting inside a survivor skips them (dot-combat's `pass_through_sets`, API level 2); stand-ins hold fire for a friend's hitboxes in the line.
- Stand-ins aim and shoot through dot-bot's `DotBotAim`; never set `command.yaw` straight onto a target. They shoot the head when only the head shows over boards.
- H is help and M is the map list: nothing in `ZzBindings` defaults to either (the medkit is G, the shove F, and an old settings file follows them through `keys.renamed`); `headless_run` and `dedicated` check it.
- A box with lasting game rules is a `ZzBoxEffect` handler named in `ZzBoxes.HANDLERS` (copy `zz_box_instakill.gd`); its `boxes.json` entry carries polarity, impact, stacks, duration, `survives_round` (keys documented in the file's `comment`). With `box_labels` off the type must never reach `ZzNetBridge`; send `loot.shown(...)`.
- **Still loading** (dot-game): `ZzGame.harm_gate`, set by the module from `can_peer_be_harmed`, is asked by `_adjust_damage` (every bite, pin, hazard, blast and bullet on a survivor; admin slay/slap carry `context.admin`), by `ZzPins.pin`, and by `ZzHorde._rebuild_candidates`, which leaves a covered seat out of the targets, so nobody is chased or spawned at it. A covered seat below the map is put back, not killed. `dedicated` checks it over a real socket; `tools/render_cover.sh` renders the cover and the frame after it lifts. The client warms every zombie look under the cover (`ZzClient._warm_zombies`).
- A cvar and a command never share a name (the cvar is `zz_box_drops`, the command `zz_boxes`).

**Survival** ([survival](docs/survival.md))
- The hold is `DotNpcDirectorWaves`, never the director's stress cycle; a wave is released by `take()` within `commons_cap`, refused spawns are owed again, it ends cleared or on `overtime`.
- A wave comes from the map's `zombie_spawns` first (`ZzHorde._wave_origin`); a release leaves room for what is queued (`pending_commons`).
- A survival map's wanderers take at most a fifth of the cap and are sent in as each wave begins. [survival](docs/survival.md#ten-waves-played-zz-survival-long-run-1-2026-10-12)
- A wave has `wave_alive_share` of the cap up at once (all of it by the last), and every mob fits under that room (`ZzHorde.wave_room`); a brute's wave draws no twist, is not down to stragglers while its brute stands, and a brute left at its overtime leaves. [survival](docs/survival.md#the-brute-that-outlived-its-wave-zz-survival-retune-2-2026-10-13)
- A barricade's boxes are `"nav": false` and `nav_for` skips them: the horde paths INTO a barricade to bash it; `headless_maps` checks both faces are on the graph.
- Nobody mends a barricade torn at in the last `ZzGame.MEND_LOCKOUT` (1.5 s); without it no wave was ever cleared. [survival](docs/survival.md#barricades)
- Barricade state goes to clients in sixteenths (BARRICADE) and at every round start; the hold as SURVIVAL every clock and on every stage change; `headless_net` follows both through the bridge.
- `survivors` in a map raises the stand-ins to that team; unsaid is 0, never 4. Commons alive: 6 per survivor for eight, 2 past them.
- Tune waves with `tools/survival_long_run.tscn` (whole holds, `--from`, `--profile`); `headless_survival` fails a big map whose wave-1 tick is over 15.6 ms.
- Bots read the map's nav annotations (`game/zz_nav_notes.gd`, dot-npc-ai's annotator, run after the bake, seeded with the spawns): stand-ins hold a chokepoint or a covered spot behind it (`zz_bot_hold_chokes`) and fall back along the route when `zz_bot_hold_overrun` zombies are on it; zombies spread over the chokes (`zz_zombie_spread`) and take drop links (`zz_zombie_drops`, `ZzNavGraph`), jump-ups only with `zz_zombie_climb`. The finder's defaults found no chokes, so the notes use width 4.5, traffic 0.07, 192 routes. Every shipped map's nav is flat at y=0, so no drop applies yet (mechanism only). `headless_nav` fails the old behaviour (holders near a chokepoint at wave start, approach spread). [survival](docs/survival.md#bots-on-the-navigation-notes)
- Suites read a map's result from `round_over`: with no intermission the next round has cleared `_decided`. [history](docs/history.md)

**The zombies' look** ([zombies](docs/zombies.md))
- After rebuilding a GLB run `godot --headless --path . --import` before anything renders it. [history](docs/history.md)
- The palette shader samples like a StandardMaterial3D (`source_color`); a survivor body plays zombie clips through `_retarget`; an attachment's offset is in the body's axes from the joint.
- `ZzZombieBody.Anim` is replicated in 5 bits: append, never insert, stop at 31. `WEARS` colours come from `tools/zombie_palette.gd`.
- Survivors are dot-player-char's people (`ZzFigure`, the zombies' kit and rig); a killed zombie falls as a skeletal ragdoll (`ZzWorldView.ragdolls`; the animated fall past the machine's cap or under `sv_ragdoll 0`); needs dot-player-char API 3. [zombies](docs/zombies.md#how-it-moves-and-falls)
- A dead survivor falls into the same yard: `ZzGame.decide_death` picks it, DEATH carries it (last, optional), `ZzClient._fall` copies the figure. One `sv_ragdoll*` set for both (`ZzGame.ragdoll_rules`, REPLICATED, followed, read by the horde). `tools/shot.sh --view=ragdoll`. [zombies](docs/zombies.md#how-it-moves-and-falls)

**The HUD and the screen** ([design](docs/design.md#the-hud-dot-uis-glance-pieces))
- Glance pieces are dot-ui's (vitals, ammo, strip, key hints, hit marker, damage numbers); naming them needs a shell with dot-ui API level 4, which `headless_run` checks.
- The HUD follows the menu's theme (`ZzHud.follow_menu`, dot-menu's `follow_hud` by name); `piece_theme()` is accent only (amber, health green); Labels set no colour of their own except accent lines.
- Every character the game writes is in the HUD's font (`headless_run` scans `game/` and `npcs/`); bars are drawn, never block characters. [design](docs/design.md#what-the-first-play-test-changed-2026-10-11)
- The top-left team-mate list is a server setting, `zz_team_roster` (`ZzConfig.team_roster`, OFF by default, REPLICATED, followed by `ZzClient.follow_roster`); the Tab board carries each survivor's Health and Downs left (`ZzClient.health_text`/`downs_text`) so nothing is lost with it off.
- Feed lines go through `ZzClient.feed_line`: "You are down", never "You is down".
- A hit is drawn only from the server's confirmation (`ZzGame.hit_landed`): marker, number, zee's red burst (`ZzClient._draw_body_hit`); the number is real health, borrowed is the white length. [design](docs/design.md#the-hud-dot-uis-glance-pieces)
- Right mouse aims down the sights (`ZzBindings.AIM`), presentation only; the lens zooms from `ZzClient.base_fov` (where the menu's field of view binds, never the camera); the shove is F alone. `tools/shot.sh --view=ads`. [design](docs/design.md#down-the-sights)
- The health plate ends 206 px off the bottom, above a full chat log (202); `headless_run` checks the arithmetic.
- Between a decided map and the next the strip counts down (`next_round_seconds`, sent in ROUND).
- `mp_solidplayers` and `mp_forceview` are REPLICATED and followed through the link; third-person and spectate cameras stop against the world. [design](docs/design.md#cameras-and-bodies)
- A night map draws its own sky (`ZzMap._dress_night_sky`: stars, a moon where the moonlight comes from); the fog and fill keep the map's numbers. Night maps stay night; render both renderers before changing a light number.
- A gate may `look` like chain-link and a `use` objective may be a `prop` (padlock on its gate, lever, radio) from `zz_fixtures.gd`; pictures only, the box still collides.

**Delivery** ([design](docs/design.md#delivery-and-the-map-vote))
- `project.godot` carries no comments (the editor drops them); gravity is `ZzConfig.gravity` on the world's own space; the renderer is `gl_compatibility`; texture imports keep `detect_3d/compress_to=0`.
- **Baked light** (dot-lighting's `DotLightBake`): `lightmaps/<id>.res`, one per map, is tracked and ships in THIS pack (the maps pack is server-only, `maps_delivery: server`), found through `ZzPaths.rebase`. Every opaque box batch has UV2 from `DotLightmapSheet` and is named `Boxes_<n>`; a bake whose fingerprint (`ZzMap.light_fingerprint`: boxes, lights, environment, `BAKE_VERSION`) is not the document's is refused with a WARN and the map is drawn with live lamps, as is a map with none (workshop maps). Baked, the lamps turn `BAKE_STATIC` and still light zombies and props; the moon or sun stays live. **Edit a map's boxes or lights, then rebake**: `tools/bake_lightmaps.sh [ids]` (on the GPU box through `../gpu.sh`; seconds per map) and commit `lightmaps/`; `headless_maps`' "baked light" section fails on a stale bake. The dot-lighting editor plugin is enabled in `project.godot` for this and does nothing without its flag. Big maps bake at `texel_scale` 0.5 (`tools/lightmap_scenes.gd` SETTINGS) to keep the download near 14 MB for all thirteen (every map the game ships, `headless_maps` checks). **Static props** (`Prop_*`) and brushed-metal batches (`Shiny_*`) are bake-time casters: they cast and bounce into the boxes' lightmap, then `tools/lightmap_trim.gd` (run by `bake_lightmaps.sh`) removes them from the bake so no node is left unmatched. Metal stays live-lit because its look is a lamp's highlight, which a lightmap (diffuse only) cannot hold. Everything that moves is lit by the probes and live lamps. **Brightness and tint**: a lightmap ignores the Environment ambient, and a closed room has no sky for the bake's sky term to show, so every surface emits the live ambient colour in the bake (`EMIT_BY_MAP`; open maps also take a sky term, `AMBIENT_GAIN_BY_MAP`) and the day is carried by a tonemap exposure rise (`ZzMap.BAKED_DAY_EXPOSURE`). Both tables are tuned per map so a baked frame matches the live one in brightness and colour: compare `tools/shot.sh --no-bake` (live) against the default (baked), `--day=0..1`. An unlit-by-ambient bake reads olive (warm lamps only), so never tune away a tint with exposure. Bake on the GPU box with `GPU_BOX=staging02`. A map absent from both tables bakes at the defaults (emit 0.4, sky gain 6.0), which is far too bright for an open night map: ze_jurassicpark read as a flat bright plain under a dark sky until it got its own row (a stale bake is NOT the cause: it logs a WARN and `headless_maps` fails it). Changing props or `BAKE_VERSION` makes every bake stale.
- **Drawn worlds** (zombie-zone-maps' `tools/build_worlds.py`): a converted map's document may name `"world": "zz_world_<id>"`, its own faces as dot-map's `dot-bsp-mesh`, a pack of its own. The client draws it, never the server: `ZzClient._draw_world` holds the load gate (`&"world"`) while `ZzMap.load_world` reads `res://world/<pack>/` (the local link, `# bootstrap-link: zombie-zone-maps/world`, not in CI) or fetches the key `ZzGame.build_map` put in the document (`world_key`, from `ZzModule._world_key`: the maps mount's owner and version) through `DotGameContent.ensure_one`. Drawn only: the boxes still collide and cut the horde's ground; `attach_world` frees the `Boxes_*`/`Shiny_*` batches, removes the bake (no UV2 on the mesh yet) and turns the lamps live, and keeps `zz.keep_boxes` drawn. Any failure is a WARN and the boxes stay. `tools/shot.sh --no-world` draws the boxes. A solo map from a delivered pack has no server to name the key, so it draws boxes unless the world is linked locally.
- **Moving parts** (`ZzMechanics`, built from the drawn world's manifest by `ZzMap.attach_mechanics`; the dev server builds it from the local `world/` link, a delivered pack without `world/` has none, and a client that draws no world gets none). A mover is a StaticBody3D whose pose is a pure function of `(start_tick, fraction, dir, locked)` and the tick, posed per tick with `body_set_state`; the server steps buttons, `trigger_multiple`/`trigger_once` volumes and the links graph (delays kept, unsupported inputs and volume kinds noted once at DEBUG), and every change goes out as `ZzEvents.Kind.MOVER` (resent to joiners). A rider is carried by the platform's pose change in `ZzPlayer._ride`, after the motor and in replays too (`ZzController.before_fn` poses movers first). Not carried yet: spinners, zombies; the horde's nav ignores movers. `headless_mechanics` plays the real 4-way lifts and a door.
- The maps pack is named by the server owner, never by `game.yml`; `ZzModule` adds every mount's `maps/` at load and after `zz_reload`.
- **Workshop maps** (`provides.json`: `accepts.map_kinds` `survival` and `exodus`): a pack's `map` entry's `scene` is a ZZ map DOCUMENT (JSON, same as `maps/`) whose `id` equals the entry's. `ZzCatalogue.follow_content` reads `DotContentIndex.shared()` on every `playable()`, so a subscribed map (solo) is validated, nav-graphed and played like the game's own, shown "Name [Pack]"; the game's own ids win, a bad document lands in `catalogue.refused` and is not listed, and online lists none. The ballot lists them through dot-vote's `follow_content`, so `maps_fn` leaves them out. `headless_workshop` holds it.
- Under MANUAL `ZzVote` opens a passed rock-the-vote itself, and `_game_load` refreshes the map list after the delivered maps; the match answers `round_in_progress_fn` by name.

## Team damage, votebans and barricades

`ZzConfig.friendly_fire_mode` (`zz_friendly_fire_mode`): 0 off, 1 on, 2 (default) a new player's team damage is reflected onto themselves, 3 everybody's. New is lifetime playtime under `zz_rookie_minutes` (achievements progress, session seconds as a floor). `ZzTeamDamage` adds a person's team damage over `zz_team_damage_window` seconds (counted before reflection; stand-ins never counted): `zz_team_damage_vote` starts a voteban through dot-vote's `DotVoteBans.start` (loaded by path, so a host with an older dot-vote runs without), `zz_team_damage_ban` bans for `zz_team_damage_ban_minutes`, staff immune. Reflection redirects `damage.victim` in `ZzGame._adjust_damage`, after the friendly scale. Barricades are their own physics layer so `zz_pass_barricades` (default on, replicated) can drop it from survivors' masks only. Exodus maps seat at least `zz_exodus_team` (8) survivors, stand-ins filling.

## Validating

```bash
./game.sh test                                          # parse, then every suite
python3 ../zombie-zone-maps/tools/build_maps.py --check
tools/bake_lightmaps.sh zz_lot                           # rebake one map's light (the GPU box); BAKE_LOCAL=1 for here
godot --headless --path . res://tools/survival_long_run.tscn -- --map=zz_high_school [--from=7] [--profile] [--watch=30 --detail]
tools/server_probe.sh [16 32 64 100 128]   # server tick by phase, N peers plus the horde, 64 and 33 Hz ([survival](docs/survival.md#the-server-tick-at-16-to-128-survivors-zz-scale-probe-1-2026-10-19))
xvfb-run -a godot --path . res://tools/audio_probe.tscn
tools/shot.sh --view=overview --zz-map-ids=zz_blackout_1
tools/shot.sh --view=room --alone --zz-map-ids=zz_blackout_1 --at=16.6,1.6,65.4 --look=18,1.1,66   # the fence and its padlock
tools/shot.sh --view=wave --zz-map-ids=zz_high_school --zz-survival-warmup-seconds=3 --seconds=60 --at=-3,0.05,11 --look=-3,1,16
tools/shot.sh --view=hit --spawn=common:6               # team bars, marker, number, borrowed health, a hold-out clock
tools/camera_check.sh --render
tools/shot.sh --view=third --spawn=brute:1,leaper:1
tools/shot.sh --view=pinned --pin=ride --pin-me
xvfb-run -a godot --path . --script tools/zombie_rack.gd -- --set=horde --at=5    # also --kinds=..., --set=commons, --set=deaths
tools/shot.sh --view=weapons --weapons=all --out=res://screenshots/weapons
tools/shot.sh --view=ads --out=res://screenshots/ads              # hip, raising, aimed: an iron sight and a scope
tools/shot.sh --view=ragdoll --reaction=face_plant --seconds=2.5   # a stand-in killed and its fall
```

Without `maps/` linked in (CI clones this repository alone) `headless_maps` checks the practice street only, and says so.

## Still to do

1. **Put it live**: the tag and shell order is in [design](docs/design.md#putting-it-live).
2. **Bile that turns the horde on itself**: a splashed common is drawn (FLAG_BILED) but no brain targets another zombie yet.
3. **More box outcomes**, written by the owner, toward the hundred.
4. **Play it with people**, and set normal's numbers from that.
5. **Left alone on purpose**: stand-ins converging on one pinned or downed friend (zz-bots-helpers-1, needs long measurements); `zz_trace.gd` is gone ([history](docs/history.md)).
