# game-zombie-zone

A co-operative zombie shooter: a team of survivors crosses a map from safe room to safe room (or holds a survival map for its clock) against a directed horde, eight kinds of special infected with one trick each, and boxes the zombies drop that do something random. Hardcore by default: friendly fire on, three downs and you are dead, a horde that circles you rather than queueing.

Read the family-wide conventions in [`../../CLAUDE.md`](../../CLAUDE.md) first, and each addon's own `CLAUDE.md` before working in it (dot-npc, dot-npc-ai and dot-npc-ai-director most of all). This file is only about what this game decides. The maps are in `maps/`, a link to [zombie-zone-maps](../zombie-zone-maps), written by its `tools/build_maps.py`; `maps/README.md` there is the format.

**Built 2026-10-10 from mg-prop-hunt's skeleton** (module, services, wire, client, HUD, spectate, progress, avatars, figure, vote, map documents and props, renamed `ph` → `zz` and then rewritten wherever they named a disguise, a hunter or a taunt). Where a comment says "mg-wipeout found…" or "another game in this family…", the finding is that game's and the line was kept because it is still true here.

The design brief was the genre's own: the four-player co-operative zombie campaigns, the specials that punish a team that splits up, and the big community servers that ran them with twenty-odd players, harder specials, more frequent hordes and a hundred kinds of "party box" that zombies dropped (gamemann's own l4d2-partyboxes plugin is one of them). None of that is named in a public file; see the family rule.

## Layout

```
game/
  zz_config.gd       every rule a map is played under: difficulty, downs, horde, specials, boxes, bots
  zz_map_doc.gd      what a map IS: boxes, props, lights, spawns, safe areas, route, nav, items, objectives
  zz_map.gd          a document built: solid boxes, gates as separate bodies, props, areas
  zz_catalogue.gd    every map the server has, and the built-in practice street
  zz_npcs.gd         the zombie catalogue (nine kinds), and the nav graph a map's document gives
  zz_horde.gd        the horde: spawner, director, senses, squads, sounds; mobs, specials, brutes, sleepers
  zz_pins.gd         being held: pounce, choke, carry, ride
  zz_hazards.gd      acid, fire, healing zones; spit, rocks, pipe bombs, shells, molotovs in flight
  zz_loot.gd         what lies on the ground and what using it does
  zz_boxes.gd        the boxes: boxes/boxes.json read and checked, ~40 verbs, stacking effects
  zz_weapons.gd      every weapon by tier, from every weapon pack (the seam for a second pack)
  zz_bots.gd         stand-in survivors
  zz_controller.gd   DotFpsController with the game's modifiers (pinned, down, limp, haste, knock...)
  zz_player.gd       one survivor: life, downs, borrowed health, pin, hands, status, stats
  zz_game.gd         the simulation: map flow, combat, hands (use/heal/pills/shove), downs, objectives
  zz_hud.gd zz_world_view.gd zz_client.gd zz_audio.gd   what a person sees and hears
  zz_module.gd       the DotGameModule: cvars, console and admin commands, stand-ins
  net/               the codec (NPC, PIN, LOOT, BOX, HAZARD, BLAST...), player and zombie behaviours, the bridge
npcs/                the zombie body, its view, and one brain script per kind (by path)
boxes/boxes.json     the box types and every outcome; an owner edits it
props/               kits.json (which Kenney models, at what scale), catalogue.json (measured), pieces.json (each prop's collision pieces, dot-props' DotPropPieces; tools/measure_props.gd writes both, about four minutes)
sounds/              moans, specials, music; CREDITS.md
examples/            headless_run (126), headless_maps (61), headless_net (67), headless_weapons (17), dedicated (59)
tools/               shot.sh/.gd (render a view), zombie_rack.gd, convert_bodies.gd, audio_probe
```

## Decision 1: the zombies are the server's, and a client draws them

dot-npc's reason, which is stronger here than anywhere: a zombie's position is a pathfinder, a steering pass and a crowd pushing on it, none of which is reproducible on two machines. So zombies are **not predicted**. Each one is a `DotNetIdentity` with `ZzNpcNet` (position, yaw, health, state, animation, flags) and is **always relevant**: a crowd half sent is a crowd with holes in it. A client is told a zombie exists (NPC, with its kind and variant so the body is chosen once), interpolates its snapshots, and is told when it is gone and whether it died (NPC_GONE), so a body can fall rather than vanish. `headless_net` spawns one, moves it on the server, and checks the client's copy is within 0.6 m and that its death arrives as a death.

The survivors **are** predicted (dot-player-controller), and everything that changes how a survivor moves is a controller **modifier** (`ZzController`: PINNED, DOWN, LIMP, TAGGED, BUSY, HASTE, LOW_GRAVITY, HEAVY and eight KNOCK directions), because a modifier is replicated with the state and the client applies it on the same tick the server does. A pin or a knock written as a velocity on one end only is a survivor pulled back every tick.

## Decision 2: the zombies' ground is the map's own floor plan

A map document carries `nav.floors` (rectangles), and `ZzNpcs.nav_for` lays dot-npc's point graph over them and cuts out every solid box and every prop taller than half a metre, and every **shut gate**. Opening a gate rebuilds the graph without it (`ZzHorde.open_gate`), which is what lets a barrier hold the horde back and then let it through. zombie-zone-maps generates `nav.floors` from the same regions the walls come from, so the two plans cannot drift; `headless_maps` checks, on every map, that the graph joins every objective, sleeper, spawn hint and the end area to the start, and that the end is cut off while the gates are shut.

**A mob is only spawned where it can reach somebody** (`ZzHorde._reaches_somebody`, by the graph's connected pieces), and **never inside a safe room** (`_keep_out_of_safe_rooms`). Both were found by `dedicated`: the hold-out's mob spawned behind the barrier the hold-out was opening (`headless_run` arms it: 40 of 40 spawns stranded without the check), and six wanderers stood waiting in the end room. Nothing errored; the stand-ins held the switch with nothing to shoot.

**dot-npc changed for this game**, and its [navigation](../dot-npc/docs/navigation.md) and [history](../dot-npc/docs/history.md) docs have each: bucketed indexes for thousands of points, a binary-heap A*, de-duplication by distance (the old grid key split the graph at doorways and cut the start room off), partial paths that wait instead of repathing every tick (100 ms a tick with a crowd at a shut gate), connected-piece labels so an unreachable goal costs nothing, and `eye_height` (sight was cast from the feet, which start on the floor, so every NPC was blind).

## Decision 3: the director paces, the commons crowd, the specials wait

- **Commons** idle in kinds (stand, sit, feed, mill, shamble) with an alertness drawn per zombie; one that sees a survivor screams, and the scream wakes everything within earshot (`spread_alert`). Only `attackers_per_survivor` (6) take an attack slot on one survivor; the rest take a place on a ring round them, so a crowd surrounds instead of queueing in a line. A mob is a burst spread over a few seconds from points out of sight, ahead of the team along the map's `route` (dot-npc-ai-director's flow) and behind it.
- **Specials** pick a victim by a score (alone, far from the team, already hurt, not already held) and wait up to six seconds for a good moment (`ready_to_strike`): a leaper from cover, a strangler with a clear line, a ram with a straight run. A special that attacks the moment it sees somebody is a special the team kills on sight.
- **The brute** is its own event, with its own music and health scaled by the team.
- **The sleeper** sits until somebody comes too close, then goes for that one person.

Every number is a cvar or a `zz_config.gd` field, and difficulty scales what a hit does (`damage_scale`: 0.35, 1, 2.5, 5) and friendly fire with it.

## Decision 4: down is not dead, and borrowed health is inside the health

At zero health a survivor goes **down** (a pool of 300 that bleeds out, a pistol, crawling pace) up to `max_incaps` times; the next is death. A revive or pills give **borrowed health**, which drains. It is kept **inside** `DotHealth.health` with `temp_health` saying how much of it is borrowed, so dot-combat's damage, hitboxes and replication see one number; a hit takes the borrowed part first (`absorb_temp`), and a medkit replaces it with real health. A dead survivor is rescued beside the team after `rescue_seconds`.

## Decision 5: a box is data, and an outcome is a list of verbs

`boxes/boxes.json` is the whole content: types, each with weighted outcomes, each a title, a message and a list of actions such as `{"do": "airstrike", "target": "nearest", "count": 3, "damage": 60}`. `ZzBoxes.load_text` refuses a file with a verb it does not have (so a typo is a refused file with a reason, not a box that silently does nothing), and `_do_<verb>` is one function per verb. `who` selects opener / team / nearest / random / downed / dead. **Lasting effects stack**: two "double the mobs" are four times, each wearing off on its own clock; the HUD lists them, grouped, by the name of who they are on. `headless_run` runs every outcome of every box once against a live map. The owner is meant to write most of the hundred kinds; the shipped 76 are a start and an example of every verb.

## Decision 6: a second weapon pack is a list, not a fork

The server carries two packs: zee-dot-weapons and zed-dot-weapons (built for this game, 2026-10-10). zee builds every rig's catalogue, every world model's art and every report from its own tables, so a second pack registers into those (`ZeeWeaponPack.add_source` and friends, added to zee for this) and `ZzWeapons.use_packs` is the one line here that names it, called by the world before any rig is built because a rig reads its catalogue once. `ZzConfig.second_weapon_pack` turns it off. `ZzWeapons` sorts everything into tiers by **tag** (`sidearm`, `primary`, `heavy`, `melee`, `thrown`), so loot, the boxes' "upgrade" and "heavy weapon", and the stand-ins' "is this better" mix both packs without a list.

**What a weapon puts into the world goes through `ZzGame._throw`**, and until it existed nothing did: `_advance_weapons` resolved `outcome.shots` and dropped `outcome.spawns`, so every frag, sticky charge and launcher shell in zee cost ammunition and did nothing. A spawn becomes one of `ZzHazards`' projectiles by its weapon's tags: `molotov` a fire, `pipe_bomb` a beeping lure that goes off, `bile` a jar the horde comes to, anything else a GRENADE on its fuse (resting where it lands), or a ROCKET when it barely drops (flown straight on both ends; the client is told only a start and a velocity). A weapon tagged `incendiary` (the flamethrower) sets what it hits alight (`ZzHorde._on_damage_applied`). `headless_run`'s "both weapon packs, and what they throw" throws each one at commons.

## Decision 7: stand-ins play the map, and do not shoot through you

`ZzBots` drives a survivor with the same commands a person sends, in priority order: a pinned friend, a downed friend, a threat (or a shove when crowded), pills or a medkit, reload, something better on the ground, the objective, then the route. **A stand-in holds its fire when a friend is in the line** (`_friend_in_the_way`): before that, four of them bunched in the start room's doorway shot each other down three times in a minute with friendly fire on. A semi-automatic is fired by pulsing the trigger, or a pistol fires once. They exist to fill a server and to let `headless_run` and `dedicated` play a map; they are not meant to be clever. **How they aim and shoot is dot-bot's `DotBotAim`** (one per stand-in, on `DotBotSettings.of(game)`): the view turns at `bot_turn_rate` (walking too), a new zombie is engaged with `bot_reaction` before the first shot and `bot_aim_error` that settles, and `bot_difficulty` moves them with every other game's bots. Never set `command.yaw` straight onto a target.

## The HUD: dot-ui's glance pieces

`zz_hud.gd` draws health as a `DotVitals` (borrowed health as its `bonus`, white after the real fill; DOWN and DEAD as its `status`, all in the low colour; red at the limp line), the weapon as a `DotAmmoCounter` (an endless reserve as ∞, low at a quarter of a magazine), a hold-out's time left or a survival map's time held as a `DotScoreStrip` clock under the title, the medkit and pills as `DotKeyHints` rows with their bound keys, and confirmed hits as `DotHitMarker` and `DotDamageNumbers`. **The number is real health, not real plus borrowed**: borrowed health drains, and a number that included it would fall while nobody was hitting you; the white length says what is borrowed. **A hit is drawn only from the server's confirmation**: `ZzGame.hit_landed` (a survivor's damage applied to a zombie; never friendly fire, never the world's), sent to the shooter alone as a HIT event, connected straight to the world offline. The health plate ends 206 pixels off the bottom, above the chat box's full eight-row log (202). Colours from `ZzHud.piece_theme()`; `tools/shot.sh --view=hit --spawn=common:6` renders the marker, a number, borrowed health and a hold-out clock. Naming these classes makes the pack need a client shell with dot-ui API level 4; the derived `requires.json` asks for it and `headless_run` checks it.

## Cameras and bodies

From the first play test (survivor bots' faces filling the screen): `mp_solidplayers` (dot-player-controller, 1) puts the player layer in every survivor's motor mask through `DotPlayerBodyRules.apply_to` and gives each body a standing `SolidHull` (`ZzGame._apply_body_mask`, again on every change), so a stand-in stops at your shoulder; `mp_forceview` decides whether F5 may switch to third person. Both bound REPLICATED by the module and followed through the link. The third-person camera is a dot-core `DotCameraBoom` swept from the eye with `CHASE_UP` as `lift`, stopping against `world_mask()`; a `DotCameraFade` on the camera is handed the other survivors and finds zombies on their layer, hiding one at the lens; dot-spectate is handed the level for its chase and death cameras. `tools/camera_check.sh [--render]` flies both cameras round every spawn and route point (armed), walks the player into another with the rule on and off, and draws both views and the walk-in before and after.

## What running it found

- **Shots did no damage to zombies**: the hitboxes resolved their owner before the zombie's `DotHealth` existed. Health is created first now, then the hitboxes, then `refresh()`.
- **Idle commons never noticed anybody**: sight from the feet (dot-npc's `eye_height` fix), and the brain overwrote `sight_scale` every tick (it is the character's `alertness` now).
- **The start room had a hole in its side** a stand-in walked out of and fell; the frontage walls close it.
- **The practice street's spawns were inside its tables**, found by `headless_maps`; and zombie-zone-maps' builder stretched door floors along the wrong axis, found the same way.
- **A command and a cvar were both `zz_boxes`**; the cvar is `zz_box_drops`. **Push-to-talk and shove were both V**; shove is F.
- **Three stand-ins called Odell**: names are drawn from the ones not taken.
- **A delivered server always played the practice street first**: the world lays a map out in `_ready`, before the module adds the delivered maps, and `start()` rebuilt that one. It re-picks now when the map it holds is not one the server would choose. And **`zz_server.gd` logged `config.round_seconds`**, a prop-hunt field, as a SCRIPT ERROR no suite here loads that scene to see. Both found by dot-server-deploy's `zombiezone_client`, which joins a real client to the delivered pack.

- **H is help** (dot-menu's stock key; `ZzSettings._fill_help` writes the goal and rules), so nothing in `ZzBindings` may default to H; the medkit moved to G on 2026-10-11 and `headless_run` checks it.
- **M is the map list** (dot-menu's map menu): `ZzGame.map_rows()` and `change_map_now()` (the next map plus dot-match's `begin_round_now`) serve both solo and the server, where dot-vote's map menu lets the owner's `sv_map_menu_flag` change it now and gives anybody else a vote. Nothing in `ZzBindings` may default to M; `headless_run` and `dedicated` check it.
- **Every `ZzEvents.Kind` must fit `ZzEvent.KIND_BITS`** (6 bits, 64 kinds); at 5, HURT and AMMO went out as HELLO and MAP for a day. `headless_net` checks it ([history](docs/history.md)).
- **A brain seeds from `npc.seed`, never `npc.instance_id`** (an object id moves with every allocation); `seed_base` is `config.seed_value`. Suites wait for a zombie's state, never time its seeded choice ([history](docs/history.md)).
- **Your gun is two rigs**: the world's (`ZzPlayer.weapons`, decides) and the client's drawn one (`ZzPlayer.view_rig`, what the HUD counts and the view model plays). Both take `ZzWeapons.command_for` (held hands, an empty magazine reloading itself); offline the buttons go onto the world's sample through `ZzPlayer.command_stamp`, never onto `controller.current_command` (sampled over); the drawn rig is corrected by `correct_view_rig` once quiet. `headless_weapons` presses the client's buttons ([history](docs/history.md)).
- **A shot starting inside a survivor skips them** (`zz_trace.gd`); stand-ins test a friend's hitboxes, and `headless_run` measures them over the first round, not at 60 s ([history](docs/history.md)).

## Validating

```bash
./game.sh test                                          # parse, then all five suites
python3 ../zombie-zone-maps/tools/build_maps.py --check
xvfb-run -a godot --path . res://tools/audio_probe.tscn
tools/shot.sh --view=overview --zz-map-ids=zz_blackout_1
tools/camera_check.sh --render                          # cameras round the street (armed), mp_solidplayers both ways, views
tools/shot.sh --view=survivor --spawn=common:12
tools/shot.sh --view=third --spawn=brute:1,leaper:1
tools/shot.sh --view=pinned --pin=choke
tools/shot.sh --view=down
tools/shot.sh --view=survivor --box=mystery
tools/shot.sh --view=weapons --weapons=all --out=res://screenshots/weapons   # a fire-and-reload sheet per gun, HUD count on each tile
```

**Look**: building surfaces are Kenney's grid under dusted pastels (`ZzMaterials.PASTELS`, `DUST`), so a dark zombie reads against a pale wall; light is a dot-lighting document from the map's `environment` (`ZzMap.light_document`), the map's own moon or low sun without the rig's 0.35 daylight floor, fill at `FILL` x `ambient_energy`. Night maps stay night; check both renderers with `tools/shot.sh` before changing either number.

Without `maps/` linked in (CI clones this repository alone) `headless_maps` checks the practice street only, and says so.

**`project.godot` carries no comments**: the editor drops them, and any key left at its default, the first time it saves the file, so the reasons for its settings live here. Gravity is left at the engine default and nothing reads it: `ZzConfig.gravity` is written onto the world's own physics space, because a project setting does not travel inside a delivered pack. The renderer is `gl_compatibility` because that is what the delivered client runs, and lighting is tuned under it. The canvas texture filter is Nearest so the prototype grid reads as discrete squares at distance. Texture imports keep `detect_3d/compress_to=0` (and `[importer_defaults]` starts new ones that way) so the editor never re-imports one VRAM-compressed on a first open.

## Delivery

The maps are their own repository and pack, [zombie-zone-maps](../zombie-zone-maps): `maps/` here is a dot-bootstrap link, and `game.yml` does not name the pack; the server owner names `gamemann/zombie-zone-maps` (or their own) in their deployment's map config, and `ZzModule` adds every mount's `maps/` to the catalogue at load and after every `zz_reload`. A client is sent the one document being played. No `class_name` anywhere in `game/` or `npcs/`, because a mounted pack cannot register one; the brains are named by path.

**The map vote** (`game/zz_vote.gd`, MANUAL, applied at a round's end): under MANUAL `ZzVote` opens a passed rock-the-vote itself (dot-vote does not; `rtv_delay_sec` 0), and `_game_load` refreshes the map list after `_add_delivered_maps`. Without either, `!rtv` answers "Rocked. 1 of 1." and nothing opens, or a delivered server's ballot holds only the practice map and never opens. `examples/dedicated` arms both. The match answers dot-vote's `round_in_progress_fn` (`world.match_node.is_live()`, set by name because an older shell's dot-vote lacks it), so a `time_up: finish_round` limit that runs out in warmup or between rounds changes at once instead of holding for `finish_round_max_sec`; `dedicated` checks both halves.

## Still to do

1. **Put it live.** The client shell needs dot-ui API level 4 (the HUD names its glance pieces). The GitHub repositories (`zees-games/game-zombie-zone`, `zees-games/zombie-zone-maps`, `zees-games/zed-dot-weapons`) exist; tag zee-dot-weapons (its `add_source`) and zed, add `content/zombiezone/` and a client example to dot-server-deploy, tag dot-npc (and anything else changed) and rebuild the shell, publish the maps pack before the game.
2. **Bile that turns the horde on itself**: a splashed common is drawn (FLAG_BILED) but no common's brain targets another zombie yet.
3. **More box outcomes**, written by the owner, toward the hundred.
4. **Play it with people**, and set normal's numbers from that.
