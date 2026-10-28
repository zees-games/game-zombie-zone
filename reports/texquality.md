# Zombie Zone texture density (texquality, real store widths)

Run 2026-10-27 with `bsp.py texquality <world mesh> --store zombie-zone-maps/.stores/pbr-library` on all 37 converted maps. Drawn px/m is the slice albedo width over the 2 m one repeat covers (triplanar). No map has any PBR area under the 256 px/m target. Sorted by the worst blur ratio (drawn px/m over the original's) among sets listed as blurrier than the original.

| map | PBR m2 | drawn p5/p50/p95 | original p5/p50/p95 | blurrier sets m2 | worst set (ratio) | set, tier, drawn vs original px/m, m2 |
|---|---|---|---|---|---|---|
| zm_abandoned_mall | 45244 | 512/1024/1024 | 148/210/210 | 46.5 | 0.14 | WoodFloor039 1k 512 vs 3535, 2.2 |
| ze_death_star_escape | 204818 | 512/512/512 | 58/159/210 | 1.8 | 0.15 | wooden_barrel 1k 512 vs 3360, 0.0 |
| ze_biohazard_manor | 127994 | 512/1024/1024 | 119/199/237 | 0.1 | 0.20 | Rock049 1k 512 vs 2590, 0.1 |
| zm_roy_highway | 94369 | 512/1024/1024 | 24/104/210 | 0.1 | 0.27 | Metal028 1k 512 vs 1864, 0.0 |
| zm_blockfort | 21399 | 512/512/1024 | 1/209/295 | 0.6 | 0.30 | Snow014 1k 512 vs 1680, 0.6 |
| zm_house_outbreak | 12378 | 512/512/1024 | 177/210/212 | 0.5 | 0.31 | MetalPlates009 1k 512 vs 1669, 0.5 |
| zm_officeattack | 14842 | 512/512/1024 | 177/210/210 | 1.9 | 0.32 | PaintedWood007A 1k 512 vs 1615, 1.9 |
| zm_krusty_krab | 21772 | 512/512/1024 | 52/148/274 | 7.2 | 0.44 | Metal011 1k 512 vs 1158, 7.2 |
| zm_hellarch | 21268 | 512/1024/1024 | 52/209/210 | 0.2 | 0.49 | Tiles091 1k 512 vs 1044, 0.2 |
| zm_antarctic_hospital | 21194 | 512/1024/1024 | 65/210/241 | 2.7 | 0.50 | wooden_barrel 1k 512 vs 1029, 2.7 |
| zs_verystill | 19890 | 512/512/512 | 52/210/253 | 0.0 | 9.00 | - |
| zs_slugde | 12325 | 512/1024/1024 | 50/210/210 | 0.0 | 9.00 | - |
| zs_ravenstreet | 0 | 0/0/0 | 0/0/0 | 0.0 | 9.00 | - |
| zs_lens | 11264 | 512/1024/1024 | 149/150/210 | 0.0 | 9.00 | - |
| zs_krusty_krab_large | 19454 | 512/512/1024 | 52/151/280 | 0.0 | 9.00 | - |
| zs_goth_house | 5615 | 512/1024/1024 | 181/210/420 | 0.0 | 9.00 | - |
| zs_erosion | 125143 | 512/1024/1024 | 22/52/145 | 0.0 | 9.00 | - |
| zm_roy_the_ship | 21746 | 512/1024/1024 | 104/210/210 | 0.0 | 9.00 | - |
| zm_pathogen | 30719 | 512/512/1024 | 49/210/210 | 0.0 | 9.00 | - |
| zm_mansion_css | 10412 | 512/1024/1024 | 202/210/437 | 0.0 | 9.00 | - |
| zm_lila_panic | 6445 | 1024/1024/1024 | 209/210/210 | 0.0 | 9.00 | - |
| zm_day_lego | 25368 | 512/1024/1024 | 207/210/210 | 0.0 | 9.00 | - |
| zm_chaos_city | 17276 | 512/512/1024 | 117/210/210 | 0.0 | 9.00 | - |
| zm_atix_helicopter | 18305 | 512/512/1024 | 20/106/210 | 0.0 | 9.00 | - |
| zm_4way_tunnel | 59661 | 512/1024/1024 | 48/172/210 | 0.0 | 9.00 | - |
| zm_16chambres | 24545 | 512/1024/1024 | 209/210/210 | 0.0 | 9.00 | - |
| ze_runforyourlife_1_v4 | 84152 | 512/1024/1024 | 15/117/210 | 0.0 | 9.00 | - |
| ze_potc | 114186 | 512/512/1024 | 50/102/210 | 0.0 | 9.00 | - |
| ze_nuke_beta | 14586 | 512/512/1024 | 105/210/420 | 0.0 | 9.00 | - |
| ze_jurassicpark | 109150 | 512/1024/1024 | 137/210/875 | 0.0 | 9.00 | - |
| ze_boat_escape | 240605 | 1024/1024/1024 | 210/210/210 | 0.0 | 9.00 | - |
| ze_blackmesa_escape | 81948 | 512/1024/1024 | 34/210/210 | 0.0 | 9.00 | - |
