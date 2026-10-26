# Not yet

What this game does not do yet, each with where the detail is.

- **Weapons are not accepted.** Every weapon comes from `ZzWeapons.all_defs()` (zee-dot-weapons, and zz-modern-weapons beside it, and zed when `second_weapon_pack` is on), by tier tags, and the loadout, boxes, shop and view models read that fixed list. Following `DotWeaponCatalogue.follow_content` needs `ZzWeapons` to read a catalogue instead of the pack list, and a Workshop weapon needs a tier tag and a view model the box tables can use.
