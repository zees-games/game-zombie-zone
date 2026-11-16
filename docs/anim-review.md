# Animation review

Zombie Zone's copy of the family's visual QA loop. The loop itself (the three views, 60 fps, sheets and clips, the report, posting with an `fps` metric, the defect checklist, notes until clean) is written down once in game-arena's `docs/anim-review.md` (FC); read its "The loop" and "The defect checklist" sections. This page says only what is different here. The question for every clip is: **does this look like a real game?**

## Capture

`tools/anim_review.sh <weapon[,weapon]|all|none> [--anims idle,fire] [--avatar] [--zombies kind[,kind]|all] [--fps 60] [--frames] [--soft]`, run as gamedev from the checkout or a `~/wt` worktree (`sudo -u gamedev -H tools/anim_review.sh zz_m4 --zombies common`).

- Weapons are `ZzWeapons` ids (`zz_m4`, `zz_glock`, `zz_bat`; `all` is `ZzWeapons.offered_defs()`). Each one's clips: idle, draw (from the knife, or the pistol for a melee weapon), sprint, ads, fire (trigger held 0.8 s), reload (3.2 s). Melee and thrown weapons have no ads or reload.
- `--avatar` adds the survivor's locomotion with the M4 held, driven through the real input actions: walk, strafe, run, crouch, jump (subject `avatar`).
- `--zombies` plays every infected kind (`all` is the fourteen `ZzPacks.RESERVED` kinds) on a bare grey stage: walk, run, attack, flinch (hit at 0.4 s and 1.1 s), die (limp at 0.4 s). Subject `zombie_<kind>`.
- One process cannot hold both the offline client and the stage, so `tools/anim_review_shot.sh` runs Godot once for the survivor and once for the infected, then makes the sheets and clips like FC's.

The views:

| | survivor | infected |
|---|---|---|
| `fp` | the client's own camera: arms and view model, your own body left out | the victim's eye, 1.8 m in front at 1.6 m |
| `tp` | behind-right of your body, which the client hides in first person and this script poses and shows (`ZzPlayer.present_body`) | behind-right |
| `op` | an opponent 4 m in front at eye height | its right side in profile |

Output goes to `screenshots/anim_review/`: `report.md`, `<subject>/<clip>_{fp,tp,op}_sheet.png`, `<subject>/<clip>.mp4` and `<subject>/<clip>_frames.tsv`. Post with `tools/anim_review_post.sh <review-key> --variant before|after [--only zz_m4,zombie_common] [--anims fire] [--fails]` to an item made by `nightly review new "ZZ animation review <date>" --key zz-anim-<date>`.

## The metrics

| Metric | Fails when |
|---|---|
| view pop | a view-model part (hand, arm, weapon piece) moves more than 0.04 m per 1/30 s in the eye's frame (0.09 m in a fire clip, where a shot kicks by design). A frame where the wall retract moved is not judged. |
| weapon hidden | the weapon is not shown for more than 3 frames at 30 fps (scaled to `--fps`), outside a draw |
| bone_pop, floor, slide | dot-core's `DotClipMetrics` on the third-person body, with `tools/filmstrip_thresholds.json` (the filmstrip's limits). An infected's foot slide is judged for the common one only: the stage moves every kind at the common pace, so a special's slide is printed as a note. |

The frame table has `hop` (the largest part move, `part` names it), `shown`, `wall`, and the muzzle and weapon in camera space (x right, y up, -z ahead): a muzzle that sits off the barrel or a weapon that jumps shows in those columns.

## Where a fix lives

ZZ owns the client's presentation (`game/zz_client*.gd`, `game/zz_view_grip.gd`), the infected's views and bodies (`npcs/zz_zombie_view.gd`, `npcs/zz_zombie_body.gd`, `assets/zombies/`) and its weapon defs (`game/zz_weapons.gd`). The view model and weapon poses are zee-dot-weapons (`addons/zee_weapons/view/`), the weapon art is zz-modern-weapons, and the arms and grip are dot-player-char: file a nightly item for those with the clip, the frame numbers and the sheet.
