extends DotGameNetLink

## This game's link: the shared skeleton in [DotGameNetLink], plus the names that are its own.

const ZzNetLink := preload("zz_net_link.gd")

const CHANNEL := "zz.link"

## The node name both ends must use. It is the routing, so it is a constant.
## This game's own name: every game parents its link under the same `Server` node, so two games with one name meet when a dot-server leaves the last link behind, and the newcomer is renamed `@Node@<n>` and hears nothing.
const NODE_NAME := &"ZombieZone"


func _init() -> void:
	channel = CHANNEL


static func attached_to(parent: Node, p_bridge: Node, server: bool) -> ZzNetLink:
	var link := ZzNetLink.new()
	link.name = NODE_NAME
	link.bridge = p_bridge
	link.is_server = server
	return link
