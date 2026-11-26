extends Node3D

const ZzAudio := preload("zz_audio.gd")

const ZzBoxes := preload("zz_boxes.gd")

const ZzPaths := preload("zz_paths.gd")

const ZzDefibModel := preload("zz_defib_model.gd")

const ZzGrenadeFx := preload("zz_grenade_fx.gd")

const ZzWeapons := preload("zz_weapons.gd")

const ZzNpcs := preload("zz_npcs.gd")

const ZzZombieBody := preload("../npcs/zz_zombie_body.gd")

const ZzZombieView := preload("../npcs/zz_zombie_view.gd")


const ZzPacks := preload("zz_packs.gd")


const ZzZombieLimbs := preload("../npcs/zz_zombie_limbs.gd")

const ZzZombieLod := preload("../npcs/zz_zombie_lod.gd")

## Everything a client draws in the world that is not a survivor or a wall: the zombies and their bodies, what lies on the ground, pools of acid and fire, things thrown, explosions, and a strangler's tongue. [b]Told, never asking.[/b] Offline the world's own signals call these methods;
## connected, the bridge's do, with the same arguments, so the two can only differ in where a fact came from — the shape `ZzClient._hear_the_world` already has for the rest. [b]Sound is placed here, because this is what knows where things are.[/b] A common moans now and then while it
## idles, screams on the frame it turns to RAGE, and the special's own voice plays when it appears and when it uses what it has. The sleeper's crying is a loop that follows her, so it is louder the closer you are, which is the only warning she gives.

## Seconds a killed zombie's body stays before it sinks away, when nothing gave the rules.
const CORPSE_SECONDS := 6.0

## Seconds a blast's flash lasts.
const BLAST_SECONDS := 0.6

## Gravity a thrown thing falls by on a client: the server's (`ZzHazards.GRAVITY`).
const GRAVITY := 18.0
