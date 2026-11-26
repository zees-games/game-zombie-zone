# The loadout row (bottom right)

`GSLoadoutBar` (gs-ui `hud/gs_loadout_bar.gd`, a `GSHudPiece`, API 26; promoted from this game on 2026-11-26) draws one horizontal row of slots, with the weight bar over it. It takes values only, never a game object. `ZzHud._draw_loadout` feeds it from the weapon arsenal each frame; an equal row is a no-op.

## Slot API

`set_slots(Array)`, each element a Dictionary:

| key | type | meaning |
| --- | --- | --- |
| `key` | String | the key cap; `""` for none |
| `icon` | Texture2D | exactly one picture per slot; weapons use `ZzShopIcons.icon_for(def.id)` (rendered from the model). `null` draws `name` |
| `glyph` | StringName | `&"medkit"` or `&"pills"`: a drawn picture for a kit slot that has no model; used when `icon` is null |
| `name` | String | shown only when there is neither icon nor glyph |
| `text` | String | small line under the icon (ammo, a count) |
| `selected` | bool | in hand: eased lift and accent edge |
| `low` | bool | line in the low colour |
| `empty` | bool | faint (vacant slot, used-up kit) |
| `accent` | Color | optional selected-edge colour (a medkit may be green) |

Weapons come first; the inventory and healing work appends its medkit, pill and defib slots to the same array (up to `MAX_SLOTS` = 8). The row grows leftwards and stays anchored at the right. Give a slot one icon; never a second icon or text-only slot for the same thing.

`set_weight(carried, limit, pack, pack_max)` feeds the bar above the row (value text, `PACK n`); `clear_weight()` hides it. `footprint()` is the drawn rectangle, for placing other pieces clear of it (the ammo counter sits above `ZzHud.LOADOUT_TOP`).

Not shown anywhere on screen: speed, "SLOWED", or text boxes saying what a pickup, crate or prop does. A looked-at weapon shows only its name over its hold circle.

The widget lives in gs-ui (its docs/hud.md, "Loadout bar"); this game only feeds it.

## Kit slots and hold-to-heal

`ZzHud._append_kit_slots` appends a MEDKIT and a PILLS slot (drawn `glyph` pictures: there is no model to render; swap `glyph` for `icon` when one exists) after the weapons, with the key shown from the heal and pills bindings. A slot takes an optional `fill` (0..1), a progress bar along its foot: feed a hold-to-heal through `ZzHud.set_heal_fraction(f)` each frame (0 hides it). The kit hint rows over the health plate keep only the defibrillator. Kit slots 6 and 7 on the inventory branch use `ZzConsumables.slot_of` and the same row.
