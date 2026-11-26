The HUD spec the visual judge reads first (`gs_game_visual_judge.sh --shots ... --brief docs/hud-judge-brief.md`). Written for a judge who has never seen the game. Rendering: `tools/hud_shots.sh` on a GPU box (`heavy -- tools/hud_shots.sh`), 720p, 1080p and 1440p, states pickup, downed, loading, crawl and heal.

## Must be on screen

- **Vitals, bottom-left**: one modern cluster (health, with the temporary-health and armour readouts that belong to it). Restrained, like CS2 or Valorant, not a stack of boxes.
- **Loadout, bottom-right**: one horizontal row, **exactly one icon per slot**: weapons, then MEDKIT and PILLS (and the defibrillator when carried). A key cap per slot, a small ammo or count line under the icon of every slot except the selected weapon (its ammo is in the counter above the row, so it is deliberately not repeated; do not report that as missing or as a duplicate), the selected slot lifted with an accent edge. While a heal runs only the healing slot is accented and its count is replaced by the progress bar. The row grows leftwards from the right edge.
- **Weight**: a horizontal bar over the loadout row, with its value text. Never vertical.
- **Heal state**: the MEDKIT slot shows a progress bar along its foot while healing.
- **Downed state**: the downed HUD is recognisable (the screen treatment and status for a downed survivor), vitals and loadout still placed as normal.
- **Pickup state**: a looked-at weapon shows only its name over the hold ring at the crosshair.
- **Loading state**: the loading cover with its progress; no gameplay HUD clutter over it.

## Must never appear

- A speed readout, "SLOWED" or any speed text.
- Explanatory boxes: text panels saying what a pickup, crate, prop or kit does; key-hint walls; tooltips; debug text.
- A second icon or text-only slot for the same item.
- Two readouts of the same value.

## Quality bar

- No element touches or covers another; the ammo counter sits clear above the loadout row.
- Every icon is identifiable at a glance on its plate, including the **knife**, **medkit** and **pills** slots (a dark glyph on a dark plate is a defect; so is a pale one on a pale plate).
- Text readable at 720p. The HUD keeps the same proportion at 720p, 1080p and 1440p.
- A slot has the same place and size in every state.
