# Running a server: packs, weapon availability, spawners and the shop

Everything here is configuration. Nothing needs a code change, and an operator's files live under `cfg/server/` (or the game's own `cfg/` for a fork) so an update never overwrites them.

## Dropping in packs

A pack is an addon folder with a `spawn_provider.gd` (`zz-modern-weapons`, `zz-medieval-weapons`, `zz-historical-monsters`, or any third-party one). Put it under `addons/` (or deliver it through dot-cloud as a mount) and restart: packs are scanned at start. Weapons join the box, loot, wall-buy (supported, though no shipped map sells one), crate, spawner and trader pools; monsters join the specials.

`cfg/addons/zombie_zone/packs.yml` holds the defaults. Every `.yml` in that directory is read in name order and a later file wins, so keep your own changes in `90-server.yml` next to it:

```yaml
weapons:
  enabled: true
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

The price of a weapon is its tier's (`prices:`); a melee weapon is not sold unless `items` gives it a price. The ground shelf and the menu share the window, the stock pool (`trader_stock`) and the points.

## Configuration, the workbench and passing through teammates

Every `ZzConfig` field is a `zz_<field>` cvar (`zz_` names that were hand-written keep their code), a key in `cfg/game/game-zombie-zone/config/game.yml` (a server's own in `cfg/server/game/game-zombie-zone/config/game.yml`; a flat mapping of field names, for example `waves: 12`) and a set in the workbench. On a dedicated server an unknown key or a bad value refuses the boot. `zz_config_dump` lists every field with the layer it came from; `zz_config_diff save` writes what differs from the code defaults to `user://config_diff_game-zombie-zone.yml`, which copied to `cfg/game/game-zombie-zone/config/game.yml` becomes the shipped defaults. The per-map dictionaries (`wave_scale_by_map`, `wave_alive_share_by_map`) are not scalar and stay in the JSON file or a map's own yml.

The workbench (F9 solo or hosting a game, `workbench` in the console) is dot-game's `DotGameWorkbench`; its HTTP page is off until `workbench.enabled` in `cfg/server.yml`, and a dot-auth connect ticket of an account in `workbench.admin_uids` or `admin_groups` is accepted as the bearer.

dot-team's block rules are on when the addon is linked: survivors pass through each other (`mp_teamblock`), and `!block` / `!noblock` ask to stop or pass. Without the addon players block each other and the server logs one WARN.

Aiming down the sights (right mouse) is zee-dot-weapons' `ZeeAdsRules`: `cfg/addons/zee_weapons/ads.yml` is the shipped default and `cfg/server/addons/zee_weapons/ads.yml` overrides it per server (zoom, walk pace and spread while aimed, toggle, per-weapon rows). The server applies the pace and the tighter spread from the aim bit in the player's command, so clients predict the same pace.
