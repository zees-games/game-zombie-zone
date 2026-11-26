# The loadout row (bottom right)

`game/zz_loadout_bar.gd` (`ZzLoadoutBar`, a `GSHudPiece`) draws one horizontal row of slots, with the weight bar over it. It takes values only, never a game object. `ZzHud._draw_loadout` feeds it from the weapon arsenal each frame; an equal row is a no-op.

## Slot API

`set_slots(Array)`, each element a Dictionary:

| key | type | meaning |
| --- | --- | --- |
| `key` | String | the key cap; `""` for none |
| `icon` | Texture2D | exactly one picture per slot; weapons use `ZzShopIcons.icon_for(def.id)` (rendered from the model). `null` draws `name` |
| `name` | String | shown only when there is no icon |
| `text` | String | small line under the icon (ammo, a count) |
| `selected` | bool | in hand: eased lift and accent edge |
| `low` | bool | line in the low colour |
| `empty` | bool | faint (vacant slot, used-up kit) |
| `accent` | Color | optional selected-edge colour (a medkit may be green) |

Weapons come first; the inventory and healing work appends its medkit, pill and defib slots to the same array (up to `MAX_SLOTS` = 8). The row grows leftwards and stays anchored at the right. Give a slot one icon; never a second icon or text-only slot for the same thing.

`set_weight(carried, limit, pack, pack_max)` feeds the bar above the row (value text, `PACK n`); `clear_weight()` hides it. `footprint()` is the drawn rectangle, for placing other pieces clear of it (the ammo counter sits above `ZzHud.LOADOUT_TOP`).

Not shown anywhere on screen: speed, "SLOWED", or text boxes saying what a pickup, crate or prop does. A looked-at weapon shows only its name over its hold circle.

Promotion to gs-ui (for FC) is filed in Nightly.
