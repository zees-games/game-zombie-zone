extends RefCounted

const ZzPaths := preload("zz_paths.gd")

## The defibrillator's model, one place for the ground, the survivor's hands and the figure's.
## Origin on the floor, centred; about 0.42 m long. Its screen faces +Z, so a model with no
## turn shows its back to whoever looks down -Z.

const PATH := "res://assets/defib/defib.glb"


## A fresh copy, or null when the model is not there (the caller draws a box).
static func instantiate() -> Node3D:
	var scene := load(ZzPaths.rebase(PATH)) as PackedScene
	return scene.instantiate() as Node3D if scene != null else null
