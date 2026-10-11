# History

Bug stories worth keeping because the bug could come back. The rule each one left is in `CLAUDE.md`.

## 2026-10-10: a common's scream was counted into its run

`headless_net`'s "it comes for the survivor on the server" forced a common onto the survivor, stepped exactly one second, and wanted more than a metre moved. It failed at 0.8 m, deterministically, with the map-vote change stashed and with the controller's wall-movement edits stashed, so it looked like a regression in somebody's work.

It was neither. A forced common screams before it runs (`zz_common_brain.gd`'s alert state), for 0.35 to 0.9 s drawn off its seed plus 0.15 s for being forced: 0.5 to 1.05 s of a one-second window. The seed is `npc.instance_id`, which dot-npc's spawner takes from `body.get_instance_id()`, the Godot object id, and that id changes whenever anything earlier in the process allocates one more object. Allocating zero to seven spare `Node`s before the spawn gave screams from 0.53 to 1.05 s and results from 0.4 m to 2.3 m; two of eight passed. Any change anywhere could flip the check, which is why it passed when the suite was written and failed after unrelated commits. The distance was also measured from the asked-for spawn point, while the spawner puts the body on the floor plan about 0.6 m away, behind it.

The check now waits until the brain is in `chase` (a separate check, bounded at two seconds), then measures a second of running from where the body actually stood: 6 to 7 m at every seed tried. The threshold of 1 m was right; the window was wrong.
