# History

Bug stories worth keeping because the bug could come back. The rule each one left is in `CLAUDE.md`.

## 2026-10-10: a common's scream was counted into its run

`headless_net`'s "it comes for the survivor on the server" forced a common onto the survivor, stepped exactly one second, and wanted more than a metre moved. It failed at 0.8 m, deterministically, with the map-vote change stashed and with the controller's wall-movement edits stashed, so it looked like a regression in somebody's work.

It was neither. A forced common screams before it runs (`zz_common_brain.gd`'s alert state), for 0.35 to 0.9 s drawn off its seed plus 0.15 s for being forced: 0.5 to 1.05 s of a one-second window. The seed is `npc.instance_id`, which dot-npc's spawner takes from `body.get_instance_id()`, the Godot object id, and that id changes whenever anything earlier in the process allocates one more object. Allocating zero to seven spare `Node`s before the spawn gave screams from 0.53 to 1.05 s and results from 0.4 m to 2.3 m; two of eight passed. Any change anywhere could flip the check, which is why it passed when the suite was written and failed after unrelated commits. The distance was also measured from the asked-for spawn point, while the spawner puts the body on the floor plan about 0.6 m away, behind it.

The check now waits until the brain is in `chase` (a separate check, bounded at two seconds), then measures a second of running from where the body actually stood: 6 to 7 m at every seed tried. The threshold of 1 m was right; the window was wrong.

## 2026-10-11: four stand-ins shot each other down, and a snapshot hid it as seed luck

When dot-npc gave NPCs a stable `npc.seed`, `headless_run`'s "stand-ins play the map" went red with 0 kills and z 7 after 60 s, and the same failure could be produced on the old dot-npc by allocating one extra object per spawn. It looked like seed luck. It was two things.

The snapshot: the check read kill counters and positions once, at 60 s. Four stand-ins can lose the practice street, and the next round resets every counter and puts the team back in the start room, so a team that had killed thirty and reached the switch read as "0 kills, z 7". Even with the friendly fire below fixed, a probe over 28 NPC seed bases lost 13 first rounds inside the minute to the horde (a spitter's pool at the switch, a ram, a crowd): losing is the game. The check now samples every second and stops at the first round's end.

Why so many rounds were lost: friendly fire. Survivors do not collide with each other (the netcode's decision), so stand-ins following one path stood shoulder to shoulder or inside each other. dot-combat counts a ray that starts inside a hitbox as a hit at distance zero, so a muzzle inside a friend's head hit that friend with every shot, aimed anywhere; and `_friend_in_the_way` measured the line against the friend's middle (0.9 m up), which is well off the line when the friend is beside the gun. Instrumented, the friend was 0.7 m from the shooter's eye and 60 to 90 degrees off the aim. Six seeds out of six dealt 200 to 500 points of friendly damage in the minute and half lost the round to it. `zz_trace.gd` now leaves a survivor's hitboxes out of a shot that starts inside them (a zombie containing the muzzle is still a point-blank hit), and the friend check tests the line against each friend hitbox with a 14 degree cone for aim wobble and pellet spread. After, on nine round seeds through the suite itself: zero friendly damage, every check passing, one first round lost to the horde. "And they do not shoot each other down" (under 100 points) keeps it.

## 2026-10-11: HURT and AMMO arrived as HELLO and MAP from the first commit

Adding a HIT event for the shooter's hit marker, `headless_net` saw the server emit the hit and the client hear nothing. `ZzEvent` writes its kind in `KIND_BITS` bits, 5 since the first playable state, and `ZzEvents.Kind` had grown to 34 entries: HURT (32) and AMMO (33) were written as 0 and 1, so an online survivor's client decoded every hurt as HELLO and every ammunition refill as MAP, each on the wrong bytes. Nothing errored where anybody looked: the decoders' `ok` was false and the event dropped, so online play simply never showed which way a hit came from and never corrected a predicted magazine after a refill. Offline play does not use the wire, which is why every render looked right. `KIND_BITS` is 6 now, and `headless_net`'s codec section checks that every kind fits (armed: at 5 bits it fails, and so does the HIT check).


## 2026-10-11: offline, the counter read 15 / 60 for a whole play test

Christian's first play test (video, 2:39) showed "Dart Pistol 15 / 60" from start to finish while the pistol fired, and no reload. Three causes, stacked:

- **The client's buttons never reached the world offline.** `ZzClient._drive_offline` stamped fire and reload onto `controller.current_command` from the client's physics frame, and then the world's tick called `ZzPlayer.simulate`, which applied a fresh `sampler.sample()` over it. The world's rig (the one that resolves shots) never saw a trigger: nothing the player shot was hit (the stand-ins killed the zombies), and its magazine never moved. The client now hands the player `command_stamp`, called on the sample inside `simulate`.
- **The HUD read the wrong rig.** Offline there are two rigs under the player: the world's, named `Weapons`, and the one the client draws with, also named `Weapons`, which Godot renames (`@Node@379`). The HUD read `^"Weapons"`, the world's, so even the drawn gun's own count never showed. The HUD reads `ZzPlayer.view_rig` now.
- **Nothing ever corrected the drawn rig.** Connected, its count was the client's own sum for the rest of the map: an ammo pile, a box, a refused shot or the next map's fresh rig (whose reserve `arsenal.clear()` left on top of the old one: 15 / 105 against the server's 15 / 60) all left it wrong. `ZzPlayer.correct_view_rig` writes the server's count onto it once it has been quiet for `VIEW_RIG_SETTLE_SEC`, from the owner's snapshot (`ZzPlayerNet`) or, offline, from the world's rig.

No suite saw it because every suite drives the world's commands itself. `headless_weapons` presses the client's own buttons (armed: without the stamp eight of its checks fail), and `headless_net`'s "a shot spends the server's magazine" builds the drawn rig a client builds (armed: without the correction three fail).

## 2026-10-12: the new zombies drew red, then black, and neither was the model

Replacing the Kenney bodies with the Quaternius kit, three bugs looked like art problems and were not.

- **Every zombie a uniform dark red.** The palette shader puts blood where the vertex-colour noise is high, and the meshes Godot drew had no vertex colours at all, so `COLOR` read white and every pixel was blood. The GLBs had them; the import was stale (`--script` runs do not reliably re-import a changed GLB first). After it was re-imported, one body was still all blood: the kit's chubby mesh carries a white colour layer of its own, which the exporter wrote instead of the painted one. The build now removes every colour layer before painting, and `CLAUDE.md` says to `--import` after a rebuild.
- **No colour swap ever matched.** The swap colours went in as a `vec3` array, which the GPU pads to four floats, so a `PackedVector3Array` was read skewed; and the shader compared against linear colours while the compatibility renderer handed back the atlas's stored sRGB values. The arrays are `vec4`, and a swap is matched in both spaces.
- **Every zombie near black on a night map**, beside lit walls. The shader then converted the atlas to linear by hand, which is not what a StandardMaterial3D does on that renderer. An A/B with a StandardMaterial3D on the same bodies showed it in one frame. The shader samples with `source_color`, like the standard material, and is lit the same.

And one that was an animation problem: the four survivor bodies, driven by the zombie's clips, were bent double at the waist, because a clip stores where a bone is and their rest pose is not the zombie's. `_retarget` moves each key from one rest onto the other.

## 2026-10-12: ninety zombies each walked the whole horde for their neighbours

Profiling the first big survival map with twelve stand-ins: a tick was 19 to 21 ms against a 64 Hz server's 15.6, two thirds of it zombies thinking, and 8 of the 10 ms of thinking was `go_to`. dot-npc-ai's crowd spacing asks its host's `npcs_near`, and dot-npc's spawner answers by walking every NPC and reading each one's position: ninety chasing commons asking every tick is eight thousand engine position reads. Nothing in the practice street's sixty-on-one suite showed it, because sixty commons standing round one survivor mostly hold the ring rather than steer. `ZzHorde` now keeps a four-metre grid of the zombies, built once a tick, and the brains (`neighbours`) and the stand-ins ask that. The stand-ins had the same shape twice: a threat scan that cast a sight line to every zombie it might prefer, and a scan with nobody in sight that was never remembered, so it ran in full every tick. Both remembered now, see [survival](survival.md#the-cost-of-a-crowd).

## 2026-10-12: a survival suite with no intermission read the next round's blank decision

`headless_survival`'s first run failed "clearing the last wave wins the map" while the log said "held through 3 waves". With `intermission_seconds` 0, dot-match ends the round and starts the next in the same tick, and the next round's `_on_round_started` clears `_decided` before the section looks. The suites read a map's result from `round_over` now, never from the world's fields after the fact.

## 2026-10-12: every map that did not name its team was built for four

Adding `survivors` to the map document with a default of 4 raised the practice street's stand-ins from the server's 3 to 4, and `dedicated` ("the module seated stand-ins up to the minimum") caught it. A map that does not say is 0 now, and only a number a map writes raises the team.

## 2026-10-12: a sprinters wave's far zombies ran at three times the pace

`ZzHorde.tick` multiplied each body's wish by the wave's speed every tick (`b.wish *= speed`), and the wish is written only when the brain thinks: a zombie thinking every second or fourth tick had its wish multiplied two or four times before the next thought (1.33⁴ is 3.1 on a sprinters wave, and a box's slow decayed far zombies toward standing still). The speed is `ZzZombieBody.speed_scale` now, applied in the move and never written onto the wish.

## 2026-10-12: zombies fell out of the mall, and `look_at` said so sixty-five times

Nothing took a zombie out below the map's `kill_y`. One that fell through the mall's floor kept falling and kept thinking, and dot-npc's `face()` handed `look_at` a position a metre could not change. The horde now removes any zombie below `kill_y` (or not at a finite position), owes a wave's again, and remembers where it last stood on the floor and whether it had just leapt (`fallen_from`, `fallen_how`; `survival_long_run` prints them per wave); dot-npc's `face()` skips such a position. One was caught falling in four mall runs, from beside a bench in the main walk; how it got through the floor (a climb onto the bench, recovery pushing it through a 0.2 m slab) is not proven.

