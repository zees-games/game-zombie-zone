extends RefCounted

## The configuration in words, for the log and the console ([method ZzConfig.describe]).


static func describe(c: Object) -> Dictionary:
	return {
		"difficulty": c.difficulty_name(),
		"horde": "%d + %d/survivor, mobs every %.0f..%.0f s" % [c.commons_base, c.commons_per_survivor,
			c.mob_interval_min, c.mob_interval_max],
		"specials": "%d + 1 per %.1f survivors, every %.0f..%.0f s" % [c.specials_base, c.survivors_per_special,
			c.special_interval_min, c.special_interval_max],
		"downs": "%d, then death; rescue %s; crawl %s" % [c.max_incaps, "off" if c.rescue_seconds <= 0.0 else "%.0f s" % c.rescue_seconds,
			"off" if c.downed_crawl_speed <= 0.0 else "%.1f m/s" % c.downed_crawl_speed],
		"boxes": "off" if not c.boxes_enabled else "%.1f%% common, %.0f%% special" % [c.box_drop_common * 100.0, c.box_drop_special * 100.0],
		"maps": "all" if c.map_ids.is_empty() else ",".join(c.map_ids),
		"bots": "%d%s" % [c.minimum_players, ", or the map's team" if c.team_from_map else ""],
		"survival": c.survival_description(),
	}
