# Running a server: packs, weapon availability, spawners and the shop

Everything here is configuration. Nothing needs a code change, and an operator's files live under `cfg/server/` (or the game's own `cfg/` for a fork) so an update never overwrites them.

## Dropping in packs

A pack is an addon folder with a `spawn_provider.gd` (`zz-modern-weapons`, `zz-medieval-weapons`, `zz-historical-monsters`, or any third-party one). Put it under `addons/` (or deliver it through dot-cloud as a mount) and restart: packs are scanned at start. Weapons join the box, loot, wall-buy (supported, though no shipped map sells one), crate, spawner and trader pools; monsters join the specials.

**The modern pack is the default set.** `zz-modern-weapons` (twenty-eight weapons with real models) is what the game hands out; zee-dot-weapons' original blasters and tools (the dart pistol, rifle, launcher, beamer and the rest) are not in the catalogue at all (only zee's fists are): not in boxes, loot, caches, spawners, the shop or the stand-ins' kits, and a box row, map pickup or `arm` that names one (`launcher`, `sniper`) gives its modern successor (`ZzWeapons.LEGACY`). The same switch covers the medieval pack, and the medieval pack is offered nowhere by default. `weapons.legacy: true` in your `90-server.yml` brings the medieval pack's weapons into every pool. The shop prices modern weapons by tier, with per-gun prices under `game.shop.items` in `spawner.yml` (revolver 150, MP5 220, combat shotgun 320, marksman rifle 450, LMG 900, grenade launcher 750, glock 90, hand cannon 260, P90 340, carbine 300, AK 380, battle rifle 520, auto shotgun 560, rocket launcher 1100, machete 70, bat 40, crowbar 60, axe 110, sledgehammer 180, hunting rifle 400); `weapons.min_wave` in `packs.yml` keeps the late guns out of boxes, caches, crates, wall-buys and spawners until a survival wave (hand cannon 2, battle rifle 3, auto shotgun 4, LMG and grenade launcher 5, rocket launcher 7; the trader is priced, not gated; exodus maps are not gated), and `weapons.rating` overrides how a stand-in ranks two guns (it takes a same-slot gun rated 1.35 times higher, fires a launcher only at a special beyond 9 m, and holds its best-rated gun otherwise); every gun's `weight` (kg) is in its profile for the planned weight system and does nothing yet.

`cfg/addons/zombie_zone/packs.yml` holds the defaults. Every `.yml` in that directory is read in name order and a later file wins, so keep your own changes in `90-server.yml` next to it:

```yaml
weapons:
  enabled: true
  legacy: false                # true: the original zee blasters and tools are offered again
  exclude: [zz_knife]          # gone from every pool
  weights:                     # draw weight, default 1; 0 is never drawn, but can still be given by name
    zz_sniper: 0.3
  tiers:                       # move a weapon between sidearm / primary / heavy / melee / thrown
    zz_vss: heavy
  not_in:                      # keep a weapon out of one channel only
    trader: [zz_sniper]
    box: [zz_knife]
monsters:
  weights: { }                 # see the file's comments
```

## Weapon availability per channel

A weapon is offered through a channel: `box`, `loot`, `cache` (the drops), `spawner` (what a map lays on the ground), `wall` (a priced wall-buy), `crate` (a map crate) and `trader` (the shelf). `weapons.not_in.<channel>` bars ids from one channel, `weapons.weights` weighs them in all. The spawner pools in `cfg/game/game-zombie-zone/dot_weapon/spawner.yml` each name their `channel:`, so adding a pool for a new use is a few lines there.

## Spawners, randomness and the shop

`cfg/game/game-zombie-zone/dot_weapon/spawner.yml` (override in `cfg/server/game/game-zombie-zone/dot_weapon/spawner.yml`; the format is dot-weapon's `docs/spawners.md`) says what each place gives:

- `pools:` the weighted lists. A `catalogue:` block adds every installed weapon with the tags, so a new pack's guns appear by themselves.
- `classes:` what a converted map's `weapon_*`, `item_*` and `ammo_*` entities become. The converter writes them into the world as `pickups`; the first matching glob wins, and its `pool`, `respawn`, `max` and `group` apply.
- `sites:` defaults by spawner id; `groups:` a cap across sites of one group.
- `game.shop.prices:` the price per weapon tier. A spawner with `data: {price: N}` sells for N points, `data: {tier_price: true}` takes the tier price. The price is drawn over the item and named in the use prompt.
- `game.trader:` shelf defaults (`pool`, `slots`, `spacing`, `restock` seconds; 0 never restocks). The stock comes from the `trader_stock` pool, so the same availability rules and packs apply.
- `maps:` per-map blocks by id or glob. Under a map, `game: traders:` and `game: spawners:` add traders and spawners without touching the map file (the shipped file has them for every world map). Shipped blocks: `ze_*` (escapes: slower gun refills, cheaper prices, no shelf), `zm_*`/`zs_*` (survival: a shelf that restocks every 150 or 180 s; the default shelf never restocks), and per map a field gun, plus a trader and a crate at the survivor spawns on a survival map; horror maps (`zm_hellarch`, `zm_pathogen`, `zm_antarctic_hospital`, `zs_goth_house`, `zm_house_outbreak`, `zm_16chambres`) slow the health and ammo refills, and city maps (`zm_chaos_city`, `zm_roy_highway`, `zm_day_lego`, `zs_erosion`, `zm_blockfort`, `zm_4way_tunnel`) refill guns every 60 s under a higher cap. A literal map id beats a glob, so an operator's own `maps:` block in `cfg/server/...` wins; a map with no block plays the defaults. `headless_maps` holds every shipped world to one weapon site, all over a floor, and a survival world to a trader.

Randomness: a draw depends on the seed, the map and the round, so the same seed gives the same items however sites tick, and every round is a new draw. Per-map scalars go in `cfg/game/game-zombie-zone/dot_map/map/<name>.yml` (or `cfg/server/...`, or `--dot-map.map.spawner_respawn_scale=2`): `spawner_enabled`, `spawner_respawn_scale`, `spawner_max_scale`, `spawner_seed` (0 derives it from the map), `spawner_pool`.

The per-map blocks above are nested `game: traders:`/`spawners:` under `maps:` in `spawner.yml`. A map document may also carry its own top-level `spawners:` and `traders:` lists (`{at, yaw?, pool?, slots?, spacing?, restock?}`); the practice street has both.

## The trader at the start

A trader stands where the map's `traders:` say (the document or `game: traders:` per map); a map with none gets one a few metres ahead of the first survivor spawn. It sells during the setup period (the start area, before the horde runs) and, by `available`, in a survival map's breathers or always. Every key is under `game: shop:` in `cfg/game/game-zombie-zone/dot_weapon/spawner.yml` (override in `cfg/server/game/game-zombie-zone/dot_weapon/spawner.yml`, or per map under `maps:`), and the first four also have a live cvar (-1 reads the file):

| Key | Cvar | Meaning |
| --- | --- | --- |
| `enabled` | `zz_trader` | 0 no trader on any map, 1 one |
| `available` | `zz_trader_when` | `setup` (0) the setup period only, `waves` (1) also a survival map's breathers, `always` (2) |
| `despawn` | `zz_trader_despawn` | true: the shelf is gone while closed; false: it stands there and says "The trader is closed." |
| `start_points` | `zz_start_points` | points every survivor starts a map with (a higher balance is kept): a number, or a table with `default`, a key per difficulty (`easy`, `normal`, `advanced`, `expert`) and a key per mode (`exodus`, `survival`; the mode wins) |
| `fallback`, `fallback_distance` | | the trader for a map with none, and how far ahead of the spawn |
| `menu`, `radius` | | E near the trader opens the menu (weapons, grenades, ammo per gun and refill, supplies, deployable boxes), listed with price, owned/full state and stats |
| `price_multiplier`, `categories`, `disabled`, `items`, `ammo`, `supplies`, `boxes`, `prices` | | prices and the list; `items: {shotgun: 300}` or `{shotgun: {enabled: false}}` per item |

### When the trader sells, and the start grace

The trader is closed while the horde is on (default `available: waves`: the setup period, the grace and a survival map's breathers). A survivor who presses E at a closed trader is told `zz_trader_closed_message`; a menu open when the round turns closes with the same sentence. Every cvar below is also a `config/game.yml` key (`cfg/game/game-zombie-zone/config/game.yml`, the server's copy of it under `cfg/server/`) and a live, savable row in the workbench; none needs a restart (the grace length is read when a map starts). `zz_grace_hud` and `zz_trader_closed_message` are replicated.

| Cvar | Default | Meaning |
| --- | --- | --- |
| `zz_trader_setup` | -1 (yes) | sells before a map starts and between maps; 1 yes, 0 no, -1 default |
| `zz_trader_grace` | -1 (yes) | sells during the start grace |
| `zz_trader_breather` | -1 (from `zz_trader_when`) | sells in a survival map's breathers |
| `zz_trader_round` | -1 (from `zz_trader_when`, no unless 2) | sells while the horde is on: the "during the round" switch |
| `zz_trader_closed_message` | `Trader closed: round in progress` | the sentence; empty is silent |
| `zz_escape_grace_seconds` | 30 | seconds after a map starts with no zombie spawned, woken or targeting anyone; 0 off |
| `zz_grace_maps` | 1 | 0 no map, 1 escape (exodus) maps only, 2 every map (a survival hold then begins after the grace) |
| `zz_grace_hud` | 1 | 1 shows "Zombies arrive in 0:23"; the end is always announced |

The grace is dot-npc-ai-director's `DotNpcDirectorGrace`, set as `director.grace`; another game uses it the same way. The default of 30 s is long enough to buy and spread out and short enough that the horde is not a pause in the map.

The price of a weapon is its tier's (`prices:`); a melee weapon is not sold unless `items` gives it a price. The ground shelf and the menu share the window, the stock pool (`trader_stock`) and the points.

## Configuration, the workbench and passing through teammates

Every `ZzConfig` field is a `zz_<field>` cvar (`zz_` names that were hand-written keep their code), a key in `cfg/game/game-zombie-zone/config/game.yml` (a server's own in `cfg/server/game/game-zombie-zone/config/game.yml`; a flat mapping of field names, for example `waves: 12`) and a set in the workbench. On a dedicated server an unknown key or a bad value refuses the boot. `zz_config_dump` lists every field with the layer it came from; `zz_config_diff save` writes what differs from the code defaults to `user://config_diff_game-zombie-zone.yml`, which copied to `cfg/game/game-zombie-zone/config/game.yml` becomes the shipped defaults. The per-map dictionaries (`wave_scale_by_map`, `wave_alive_share_by_map`) are not scalar and stay in the JSON file or a map's own yml.

The workbench (F9 solo or hosting a game, `workbench` in the console) is dot-game's `DotGameWorkbench`; its HTTP page is off until `workbench.enabled` in `cfg/server.yml`, and a dot-auth connect ticket of an account in `workbench.admin_uids` or `admin_groups` is accepted as the bearer.

dot-team's block rules are on when the addon is linked: survivors pass through each other (`mp_teamblock`), and `!block` / `!noblock` ask to stop or pass. Without the addon players block each other and the server logs one WARN.

Aiming down the sights (right mouse) is zee-dot-weapons' `ZeeAdsRules`: `cfg/addons/zee_weapons/ads.yml` is the shipped default and `cfg/server/addons/zee_weapons/ads.yml` overrides it per server. Under `ads: default:` the keys are `enabled`, `aim_time` and `zoom` (0 takes the weapon's own art; zoom is a field-of-view multiplier), `move_speed_multiplier` (walk pace while aimed, 0.8), `spread_multiplier` (0.6), `sway_multiplier` (0.5), `toggle` (hold or press-to-toggle), `view_scale` and `view_shift_x/y/z` (the drawn gun's size and offset); a `weapons:` block overrides only the keys it lists, by weapon id. **The numbers the simulation reads cross to every client** as the replicated cvar `zee_ads_rules` (a JSON line: `enabled`, `aim_time`, `move_speed_multiplier` and `spread_multiplier`, default and per weapon), so a client predicts the server's pace and spread; set it live with `zee_ads_rules '<json>'`, or edit the yml. The other keys (`zoom`, `sway_multiplier`, `toggle`, `view_*`) are the player's view and stay local. **The wire changed**: the aim bit is `ZzNetCommand.ACT_AIM` and `ACT_BITS` went from 5 to 6, so a client and a server must be the same build (the server applies the pace and the tighter spread from that bit, and the client predicts the same pace).

## Large servers: players, the horde and threads

Everything here defaults to the small-server behaviour and changes live (console, rcon, the workbench's Game settings, or a key in `cfg/server/game/game-zombie-zone/config/game.yml`).

- `zz_commons_max` (0, none): commons alive at once whatever the survivor count; `commons_cap` otherwise grows by `commons_per_survivor`.
- `zz_net_common_radius` (80) and `zz_net_special_radius` (260): metres within which a survivor is sent a common's or a special's updates. A client hides a zombie it has had no snapshot of for a second, so changing these needs no client update.
- `zz_net_far_every` (1, off) and `zz_net_far_distance` (40): everything farther than that from a survivor (other players included) is sent in one snapshot of N. 4 with 15 m is the setting for a crowded map at 100 players (see `docs/survival.md`).
- `zz_net_far_coherent` (false) and `zz_net_far_tiers` (1): with coherent on, every survivor far from a zombie skips the same snapshots of it, so the server encodes it once for all of them instead of once each; tiers add bands past `zz_net_far_distance`, each twice as far and sent half as often (`far_every` 2, tiers 3: every 2nd snapshot past 15 m, 4th past 30 m, 8th past 60 m). Keep the slowest band's gap under a second, or a client hides the zombie as unsent.
- `sv_threads_net` (off) with `sv_worker_threads` (-1, cores less one): builds each player's snapshot on worker threads, from the next snapshot. Not on the web.
- `net_native` (off) and `net_native_interest` (off): snapshots, and with the second the choice of what each survivor is sent, are built in dot-net's native library; same bytes, GDScript where the library cannot load or the interest strategy cannot be ported. Live at the console and in dot-workbench's Server threads panel.
- `sv_threads_npc` (off) with `sv_worker_threads`: runs the horde's perception passes and its repath searches on worker threads; a repath lands at the end of the think that asked it. Decisions and movement stay on the main thread. Not on the web.

`tools/server_probe.tscn` runs with `net_native` and `net_native_interest` on (`--no-native` / `--no-native-interest` for the GDScript path). `tools/server_probe.tscn -- --n=100 --acks --split --far-every=4 --far=15 --workers=4` measures a tick at a given player count.

## Navigation, stand-ins and stuck zombies

Cvars, each also a key in `config/game.yml` (live from the console or the workbench):

- `zz_nav_cache` (default 1): a built navigation graph is kept in `user://nav_cache`, keyed by the map's contents, and loaded next time; a large map takes a minute or more to build and milliseconds to load. 0 builds every time.
- `zz_nav_threads` (default 2, 0 to 16): worker tasks a graph build uses, off the main thread, so a host keeps drawing and the first build holds READY (no wave starts before the ground exists). 0, and every platform without threads, builds on the main thread in slices.
- `zz_nav_budget_ms` (default 6, 0.5 to 14): milliseconds a tick a main-thread build may take; only read when `zz_nav_threads` is 0 or there are no threads. A bottom-right "Navigation regenerating" panel shows progress.
- `zz_bot_open_boxes` (default 1): stand-ins pick up and open the boxes zombies drop; 0 leaves every box to the humans.
- `zz_bot_repress_use` (default 1): a stand-in going for a box lets go of E every few ticks so a press that missed is made again; 0 holds the key as before, and a box may then stand untouched.
- `zz_bot_idle_seconds` (default 12, 0 off): a stand-in that wants an item or a place and has neither moved nor fired nor used anything for this long gives that goal up for 30 s (or, with none, is put at its post), logged at INFO on `zz.bots`. An item within reach but behind a wall or rail is no longer stood at pressing E: after 3 s it is given up. A stand-in no longer goes for a shelf item while the trader is closed (the press is refused for good), and `idle_probe --trace=<id>` prints one stand-in's pick, reach and command each second.
- `zz_unstick_seconds` (default 4, 0 to 30): every zombie kind frees itself after this long trying to move without getting anywhere (a nudge, then a relocation); 0 turns the watchdog off.

## The creepy ambience

Each map plays a quiet mood: beds under the level and sparse one-shots (creaks, far moans, frogs, a drip) placed round the listener. The server decides, the player can only turn it down. All are cvars (`cfg/server` or the console):

| Cvar | Default | Meaning |
| --- | --- | --- |
| `zz_ambient` | 1 | 0 switches the ambience off for everyone |
| `zz_ambient_volume` | 0.5 | level; 0.5 is the files' own quiet level |
| `zz_ambient_frequency` | 1 | how often the one-shots come; 0 none, 2 twice as often |
| `zz_ambient_mood` | empty | force one mood on every map: `outdoor_night`, `indoor_hall`, `industrial`, `cave_tunnel`, `snow_wind`, `swamp`, `city_ruins`, `interior_horror` |
| `zz_ambient_indoor` | 1 | 0 stops the mood following the roof: a map's `indoor` mood is then never used |
| `zz_ambient_allowed` | empty | comma list of moods a map may use |
| `zz_ambient_dir` | empty | a directory with your own `moods.json` and sounds (format: dot-audio `docs/ambience.md`); its moods replace the built-in ones of the same name. Local to the machine that plays |

A map's mood comes from an `"ambient"` field in its document, else the hand-made maps' table, else the sound names of a converted map, else `outdoor_night`. Players have Creepy ambience, Ambience volume and Distant sounds in the Audio page.

## How fast commons chase: Hard and Angry boxes

Commons chase slowly by default. A common's chase speed starts at `zz_common_speed_base`, gains `zz_common_speed_per_hard_stack` for each stack of the Hard Box (game-wide, stacking, up to 8, lasting 2 to 4 minutes and surviving a survival wave) and stops at `zz_common_speed_max`. The Angry Box (game-wide, does not stack, 1 to 2 minutes) makes a share of the commons run at the old full speed (`zz_common_run_speed` in the config file); which commons run is fixed per zombie, so the same ones run for as long as the box lasts. Specials are not touched. The rule is the server's and zombies are never predicted, so nothing is replicated: clients only see the zombies move, and the stack count already shows in the effects strip.

| Cvar | Default | Meaning |
| --- | --- | --- |
| `zz_common_speed_scaling` | 1 | 0 restores the old behaviour: every common chases at the run speed, whatever the boxes say |
| `zz_common_speed_base` | 2.2 | chase speed in m/s with no Hard Box stack (0.5 to 15) |
| `zz_common_speed_per_hard_stack` | 0.8 | m/s gained per Hard Box stack (0 to 5) |
| `zz_common_speed_max` | 6.3 | the cap in m/s (0.5 to 15) |
| `zz_angry_runner_fraction` | 0.3 | share of commons that run while an Angry Box lasts (0 to 1) |

The two boxes are types in `boxes/boxes.json` (`hard`, `angry`; effects of the same names), so an owner can drop them, change their drop weights or duration, or add more stacks by editing that file.

## Mutants fade as Hard Box stacks rise

Mutants (every zombie kind but a common) are drawn more transparent for each Hard Box stack on: alpha is `1 - stacks * zz_mutant_fade_per_stack`, never below `zz_mutant_min_alpha`, so a mutant is never fully invisible. It is drawing only: health, hit boxes, damage and senses are unchanged, and the shadow stays solid. Every part fades together (body, worn parts, stumps and flying limbs), and the stack count changing mid-life redraws at once. The four cvars are replicated, so clients follow them; changing one takes effect on the next frame.

| Cvar | Default | Meaning |
| --- | --- | --- |
| `zz_mutant_fade` | 1 | 0 restores the old solid look for every zombie |
| `zz_mutant_min_alpha` | 0.25 | the most transparent a zombie gets (0.05 to 1) |
| `zz_mutant_fade_per_stack` | 0.1 | alpha lost per Hard Box stack (0 to 0.5) |
| `zz_common_fade` | 0 | 1 fades commons the same way (they are many, so each one costs its own material copy while faded) |

## Physics crates

Ammo piles and boxes lying on the ground are rigid bodies on the server (dot-props' `crate` toy, driven by `game/zz_crates.gd`): survivors and zombies shove them along the floor, an explosion throws them away from the blast, and a bullet knocks them. Pickup, use and buying read where the crate lies now, so they work on a moved crate, for bots too. Clients get the moved crates' places in one batched event at `zz_crate_sync_hz` and ease toward them. Crates come to rest and sleep, so a quiet map costs nothing.

| Cvar | Default | Effect |
| --- | --- | --- |
| `zz_physics_crates` | 1 | Master switch. 0 keeps every pile and box exactly where it was laid, as before. |
| `zz_crate_kinds` | `ammo,box` | Which loot kinds become crates. |
| `zz_crate_mass` | 8 | Kilograms; heavier crates are harder to push. |
| `zz_crate_push` | 1 | Multiplier on the shove from a walking survivor or zombie. 0 stops pushing. |
| `zz_crate_zombie_push` | on | Whether zombies shove crates at all (on or off). |
| `zz_crate_blast` | 1 | Multiplier on the speed an explosion gives a crate. 0 leaves them unmoved. |
| `zz_crate_max_active` | 16 | Most crates simulating at once; the longest untouched are put to sleep first. |
| `zz_crate_max_bodies` | 128 | Most crate bodies in the world; loot beyond it lies static. |
| `zz_crate_fall_limit` | 15 | Metres below where it last rested at which a crate counts as fallen out of the map (a drop over a pit). 0 waits for the map's kill height. |
| `zz_crate_lost` | rest | `rest` puts a lost crate back where it last rested (gone if it never rested), `remove` takes it away. Either way its loot entry is dropped or moved, so bots stop chasing it. |
| `zz_crate_sleep_seconds` | 2 | Seconds at rest before a crate sleeps. |
| `zz_crate_sync_hz` | 10 | Times a second the moved crates' places go out. |

The same keys are in the server file as `physics_crates`, `crate_mass` and so on.

## Carry weight

On in Zombie Zone (`zz_weight_enabled 1`; the addon itself is off for any other game); the rules are REPLICATED and live in `survivors.yml` under `weight`.

| Cvar | Default | Effect |
| --- | --- | --- |
| `zz_weight_enabled` | 1 | Master switch. Off: nothing is weighed, one weapon per slot. |
| `zz_weight_limit` | 28 | What a survivor with no backpack may carry. |
| `zz_weight_multiplier` | 1 | Every weapon weighs this much more (heavier gear for the whole server). |
| `zz_weight_slot_capacity` | 2 | Weapons one slot holds; the slot key pressed again cycles them. |
| `zz_weight_over_limit` | slow | `slow`: over the limit is slower, down to `zz_weight_slow_floor`; `drop`: the heaviest spare weapons are dropped. |
| `zz_weight_slow_floor` | 0.55 | The slowest a heavy load goes, as a share of a run. |
| `zz_weight_backpack_tiers` | `8,16,28` | Extra capacity of backpack 1, 2, 3. |
| `zz_weight_backpack_prices` | `300,600,1000` | The trader's price for each (0 or missing: not sold). A `backpack` loot kind lays them on the map. |
| `zz_weight_modifiers` | `hard=1.15,angry=1.1/0.9` | A box effect's factor per stack: `name=weight` or `name=weight/limit/add`. |

A weapon's own weight is `weight:` in its profile (workbench: the weapon's Weight field).

