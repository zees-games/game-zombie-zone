# Visual QA

Zombie Zone's use of the family's visual QA loop. The loop (three views at 60 fps, sheets and clips, the report, posting, the defect checklist, notes until clean) is written down once in dot-game's `docs/visual-qa.md`, and its driver, shot and post tools are dot-game's (`addons/dot_game/tools/dot_game_visual_qa*.sh`). This page says only what is different here. The question for every clip is: **does this look like a real game?**

## Capture

Run as gamedev from the checkout or a `~/wt` worktree:

```
bash addons/dot_game/tools/dot_game_visual_qa.sh --shot tools/visual_qa_shot.sh [--fresh all|zz_m4,zombie_common] -- \
    [--only zz_m4,zz_glock|all|none] [--clips idle,fire] [--avatar] [--zombies common,brute|all]
```

- Items are `ZzWeapons` ids (`zz_m4`, `zz_glock`, `zz_bat`; `all` is `ZzWeapons.offered_defs()`), held in turn with the carry weight limit off. Each one's clips: idle, draw (from the knife, or the pistol for a melee weapon), sprint, ads, fire (trigger held 0.8 s), reload (3.2 s). Melee and thrown weapons have no ads or reload.
- `--avatar` adds the survivor's locomotion with the M4 held, driven through the real input actions: walk, strafe, run, crouch, jump (item `avatar`).
- `--zombies` plays every infected kind (`all` is the fourteen `ZzPacks.RESERVED` kinds) on a bare grey stage: walk, run, attack, flinch (hit at 0.4 s and 1.1 s), die (limp at 0.4 s). Item `zombie_<kind>`.
- `tools/visual_qa.gd` is its own capture scene, not a `DotGameVisualQaCapture`: the survivor is staged in the real offline client. One process cannot hold both the client and the stage, so `tools/visual_qa_shot.sh` runs dot-game's shot twice, once for the survivor and once with `--zombies`.

| | survivor | infected |
|---|---|---|
| `fp` | the client's own camera: arms and view model, your own body left out | the victim's eye, 1.8 m in front at 1.6 m |
| `tp` | behind-right of your body, which the client hides in first person and the capture poses and shows (`ZzPlayer.present_body`) | behind-right |
| `op` | an opponent 4 m in front at eye height | its right side in profile |

Output is the shared layout under `screenshots/visual_qa/`. Every frame's numbers are an `ANIMFRAMES {json}` line in `capture.log`. Post with `bash addons/dot_game/tools/dot_game_visual_qa_post.sh <review-key> --variant before|after [--only zz_m4,zombie_common] [--clips fire] [--fails]`.

## The metrics

| Metric | Fails when |
|---|---|
| view pop | a view-model part (hand, arm, weapon piece) jumps more than 0.04 m per 1/30 s in the eye's frame (0.09 m in a fire clip, where a shot kicks by design), and at least 2.5 times both neighbouring frames' moves: a draw, aim or reload is fast but smooth, a pop is one frame's jump. A frame where the wall retract moved is not judged. |
| weapon hidden | the weapon is not shown for more than 3 frames at 30 fps (scaled to `--fps`), outside a draw; not judged for fists |
| bone_pop, floor, slide | dot-core's `DotClipMetrics` on the third-person body, with `tools/filmstrip_thresholds.json`. An infected's foot slide is judged for the common one only: the stage moves every kind at the common pace, so a special's slide is printed as a note. |

Each frame's line has `hop` (the largest part move, `part` names it), `shown`, `wall`, and the muzzle and weapon in camera space (x right, y up, -z ahead). A muzzle that sits off the barrel or a weapon that jumps shows up in those fields.

## Where a fix lives

ZZ owns the client's presentation (`game/zz_client*.gd`, `game/zz_view_grip.gd`), the infected's views and bodies (`npcs/zz_zombie_view.gd`, `npcs/zz_zombie_body.gd`, `assets/zombies/`) and its weapon defs (`game/zz_weapons.gd`). Fixes elsewhere get a nightly item with the clip, the frame numbers and the sheet:
- the view model, weapon poses and the held world gun and its flash (`ZeeWorldModel`): zee-dot-weapons;
- the weapon art: zz-modern-weapons;
- the figure, arms, grip and hold pose: dot-player-char.
