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

