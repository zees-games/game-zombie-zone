class_name ZzHeadScale
extends SkeletonModifier3D

## Shrinks the head bone (and the hair skinned to it) after the clip has posed it, so the kit's big-headed
## survivors read as people rather than chibi figures. A modifier, because the clip keys the bone every frame.

const HEAD_BONE := "Head"
## Below this a head is already hidden (your own body in first person): left alone.
const HIDDEN_BELOW := 0.5

var factor: float = 0.82


func _process_modification() -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	var bone := skeleton.find_bone(HEAD_BONE)
	if bone < 0:
		return
	var current := skeleton.get_bone_pose_scale(bone)
	if current.x < HIDDEN_BELOW:
		return
	skeleton.set_bone_pose_scale(bone, current * factor)


## Puts one on [param root]'s skeleton, once.
static func attach(root: Node, p_factor: float) -> void:
	for node in root.find_children("*", "Skeleton3D", true, false):
		if node.get_node_or_null(^"HeadScale") != null:
			continue
		var modifier := ZzHeadScale.new()
		modifier.name = "HeadScale"
		modifier.factor = p_factor
		node.add_child(modifier)
