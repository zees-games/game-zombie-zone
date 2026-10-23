# Running a server: packs, weapon availability, spawners and the shop

Everything here is configuration. Nothing needs a code change, and an operator's files live under `cfg/server/` (or the game's own `cfg/` for a fork) so an update never overwrites them.

## Dropping in packs

A pack is an addon folder with a `spawn_provider.gd` (`zz-modern-weapons`, `zz-medieval-weapons`, `zz-historical-monsters`, or any third-party one). Put it under `addons/` (or deliver it through dot-cloud as a mount) and restart: packs are scanned at start. Weapons join the box, loot, wall-buy, crate, spawner and trader pools; monsters join the specials.

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
- `maps:` per-map blocks by id or glob. Under a map, `game: traders:` and `game: spawners:` add traders and spawners without touching the map file (the shipped file has them for every world map). Shipped blocks: `ze_*` (escapes: slower gun refills, cheaper prices, no shelf), `zm_*`/`zs_*` (survival: a shelf that restocks every 150 or 180 s), and per map a field gun, plus a trader and a crate at the survivor spawns on a survival map; horror maps (`zm_hellarch`, `zm_pathogen`, `zm_antarctic_hospital`, `zs_goth_house`, `zm_house_outbreak`, `zm_16chambres`) slow the health and ammo refills, and city maps (`zm_chaos_city`, `zm_roy_highway`, `zm_day_lego`, `zs_erosion`, `zm_blockfort`, `zm_4way_tunnel`) refill guns every 60 s under a higher cap. A literal map id beats a glob, so an operator's own `maps:` block in `cfg/server/...` wins; a map with no block plays the defaults. `headless_maps` holds every shipped world to one weapon site, all over a floor, and a survival world to a trader.

Randomness: a draw depends on the seed, the map and the round, so the same seed gives the same items however sites tick, and every round is a new draw. Per-map scalars go in `cfg/game/game-zombie-zone/dot_map/map/<name>.yml` (or `cfg/server/...`, or `--dot-map.map.spawner_respawn_scale=2`): `spawner_enabled`, `spawner_respawn_scale`, `spawner_max_scale`, `spawner_seed` (0 derives it from the map), `spawner_pool`.

A map document may also carry its own `spawners:` and `traders:` lists (`{at, yaw?, pool?, slots?, spacing?, restock?}`); the practice street has both.
