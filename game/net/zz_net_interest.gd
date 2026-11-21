extends RefCounted

## The server's interest rule for [code]zz_net_bridge.gd[/code]: the tags a zombie entity carries, the radii
## each tag is told from, and the net_* config that tunes them. Split off the bridge (which names it
## [code]ZzNetBridge.Interest[/code]) so the bridge stays a size the efficiency gate allows.

const ZzConfig := preload("../zz_config.gd")
const ZzNpcs := preload("../zz_npcs.gd")


## Interest tags a zombie entity carries, and the radii (metres) [method make_interest] gives them.
const TAG_COMMON := "common"
const TAG_SPECIAL := "special"
## A common is a body in a crowd: fog has taken half of it by 80 m and a horde spawns within 60 m
## (`spawn_max_distance`), so past this nobody fights it. Too small pops a zombie at the edge of the
## dark, too large costs snapshot bytes (docs/survival.md).
const COMMON_RADIUS := 80.0
## A special is a threat the team plans around (a rider heard before it is seen, a sleeper), so it
## is told from further out. There are a handful, not hundreds, so the width costs little.
const SPECIAL_RADIUS := 260.0
## Players, toys and anything else with no tag.
const DEFAULT_RADIUS := 200.0


## The server's interest rule. Always relevant: players, the boss, and everything announced by event.
## Zombies are by distance (274 of 302 ms a tick at 128 survivors went to sending all of them,
## docs/survival.md), by tag through [GSNetInterestDistance] since a special needs a wider radius.
static func make_interest(config: ZzConfig = null) -> GSNetInterest:
	var interest := GSNetInterestDistance.new()
	interest.radius = DEFAULT_RADIUS
	interest.radius_by_tag = {TAG_COMMON: COMMON_RADIUS, TAG_SPECIAL: SPECIAL_RADIUS}
	apply_interest_config(interest, config)
	return interest


## Copies [param config]'s net_* radii and thinning into [param interest]; nothing without a config.
static func apply_interest_config(interest: GSNetInterest, config: ZzConfig) -> void:
	if config == null or interest == null:
		return
	if interest is GSNetInterestDistance:
		(interest as GSNetInterestDistance).radius_by_tag = {
			TAG_COMMON: config.net_common_radius, TAG_SPECIAL: config.net_special_radius,
		}
	interest.far_every = config.net_far_every
	interest.far_distance = config.net_far_distance
	interest.far_coherent = config.net_far_coherent
	interest.far_tiers = config.net_far_tiers


## The net_* fields [method apply_interest_config] copies, to tell when one changed.
static func interest_key(config: ZzConfig) -> Array:
	if config == null:
		return []
	return [config.net_common_radius, config.net_special_radius, config.net_far_every,
		config.net_far_distance, config.net_far_coherent, config.net_far_tiers]


## The shipped radius for [param kind]; the live one is the server's ZzConfig.
static func zombie_radius(kind: StringName) -> float:
	return SPECIAL_RADIUS if ZzNpcs.is_special(kind) else COMMON_RADIUS
