extends RefCounted

## The oil monster's model and its credit line (data only; the view and brain come later). Built by
## `art-src/oil_monster.py`. The mouth faces +Z as the file is (glTF's front: turn the model by PI like the mutant's view), the origin is on the floor under the core, 2.5 m tall.

const MODEL := "res://assets/zombies/zombie_oil_monster.glb"
const MODEL_LOD1 := "res://assets/zombies/zombie_oil_monster_lod1.glb"
const OIL_MONSTER_CREDITS := "Scary, Lovcraftian, Toothy, Oil-monster by lealeelu (CC-BY 4.0), modified; teeth: Tooth and spike collection by mStuff (CC0)"
## Bones: root > spine_lo > spine_mid > spine_hi > jaw. Meshes: Body, Pool (the puddle, root only), Mouth, TeethTop, TeethBottom.
## `idle` and `slide` import looping (the exporter's -loop suffix).
const CLIPS: Array[StringName] = [&"idle", &"slide", &"mouth_open", &"bite", &"grab", &"lift", &"swallow", &"flinch", &"die"]
