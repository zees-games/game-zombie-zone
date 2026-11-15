extends RefCounted
## The upper bounds the tunable cvars used to clamp to, now settings.
##
## Each cvar below has a range [lowest, highest]. The lowest is what the number means (a count is
## not negative) and stays. The highest was a hard cap; it is now the default of a setting:
## `cap_overrides` ("zz_waves=0,zz_nights=40"), where 0 is unlimited. A value outside the range is
## REFUSED with an error naming the cvar and the setting that lifts it, never clamped silently.

const RANGES := {
	"mp_killcam_time": [0.0, 30.0],
	"zz_mob_min": [10.0, 900.0],
	"zz_mob_max": [10.0, 900.0],
	"zz_special_min": [1.0, 300.0],
	"zz_special_max": [1.0, 300.0],
	"zz_brute_min": [0.0, 3600.0],
	"zz_brute_max": [0.0, 3600.0],
	"zz_screamer_mob": [0, 100],
	"zz_screamer_cooldown": [4.0, 120.0],
	"zz_crawler_grab_dps": [0.0, 50.0],
	"zz_prop_carry_mass": [0.0, 500.0],
	"zz_min_players": [0, 24],
	"zz_downed_crawl_speed": [0.0, 6.0],
	"zz_rookie_minutes": [0.0, 100000.0],
	"zz_team_damage_window": [5.0, 3600.0],
	"zz_bot_defib_reach": [1.0, 200.0],
	"zz_bot_idle_seconds": [0.0, 120.0],
	"zz_nav_threads": [0, 16],
	"zz_nav_budget_ms": [0.5, 14.0],
	"zz_unstick_seconds": [0.0, 30.0],
	"zz_nav_drop": [1.0, 10.0],
	"zz_zombie_think_range": [0.25, 4.0],
	"zz_body_stride_near": [5.0, 500.0],
	"zz_body_stride_far": [5.0, 500.0],
	"zz_dormant_from": [0.0, 1000.0],
	"zz_dormant_think_every": [8, 64],
	"zz_bot_hold_overrun": [2, 40],
	"zz_bot_helpers": [0, 16],
	"zz_bot_helper_radius": [0.0, 40.0],
	"zz_max_incaps": [0, 10],
	"zz_rescue_seconds": [0.0, 600.0],
	"zz_stuck_rescue_seconds": [0.0, 600.0],
	"zz_start_grace": [0.0, 600.0],
	"zz_survive_seconds": [0.0, 7200.0],
	"zz_retries": [0, 20],
	"zz_commons": [0, 400],
	"zz_commons_far_divisor": [1, 60],
	"zz_commons_per_survivor": [0, 50],
	"zz_wanderers": [0.0, 10.0],
	"zz_mob_size": [1, 200],
	"zz_specials": [0, 32],
	"zz_box_carry": [0, 6],
	"zz_box_deploy_seconds": [0.5, 15.0],
	"zz_revive_seconds": [0.5, 30.0],
	"zz_revive_range": [0.5, 5.0],
	"zz_revive_health": [1.0, 100.0],
	"zz_revive_bleed_per_second": [0.0, 100.0],
	"zz_defib_charge_seconds": [0.5, 30.0],
	"zz_defib_range": [0.5, 5.0],
	"zz_defib_invulnerable_seconds": [0.0, 15.0],
	"zz_defib_cooldown_seconds": [0.0, 120.0],
	"zz_defib_max_body_age": [0.0, 600.0],
	"zz_defib_move_tolerance": [0.1, 3.0],
	"zz_defib_price": [0, 100000],
	"zz_defib_hear_range": [0.0, 100.0],
	"zz_common_speed_base": [0.5, 15.0],
	"zz_common_speed_per_hard_stack": [0.0, 5.0],
	"zz_common_speed_max": [0.5, 15.0],
	"zz_box_instakill_special_scale": [1.0, 100.0],
	"zz_waves": [1, 50],
	"zz_nights": [1, 20],
	"zz_breather": [0.0, 300.0],
	"zz_prestart_time": [0.0, 300.0],
	"zz_infect_after": [0.0, 600.0],
	"zz_infect_count": [1, 32],
	"zz_survival_warmup": [-1.0, 300.0],
	"zz_respawn_base": [0.0, 600.0],
	"zz_respawn_min": [0.0, 600.0],
	"zz_respawn_max": [0.0, 600.0],
	"zz_respawn_healthy_scale": [0.0, 10.0],
	"zz_respawn_scarce_scale": [0.0, 10.0],
	"zz_respawn_per_wave": [0.0, 120.0],
	"zz_respawn_protect": [0.0, 30.0],
	"zz_day_seconds": [10.0, 900.0],
	"zz_night_seconds": [10.0, 1800.0],
	"zz_wave_size": [1, 400],
	"zz_wave_size_per_survivor": [0, 50],
	"zz_wave_growth": [0.0, 2.0],
	"zz_brute_every": [0, 50],
	"zz_barricade_health": [10.0, 10000.0],
	"zz_barricade_bash": [0.0, 200.0],
}


## The parsed `cap_overrides`: cvar name -> highest allowed (0 = unlimited). Fails loudly: an entry
## that is not `zz_name=number`, or names no capped cvar, comes back in [param errors].
static func parse_overrides(text: String, errors: PackedStringArray) -> Dictionary:
	var out := {}
	for entry in text.split(",", false):
		var parts := entry.strip_edges().split("=")
		var known: bool = parts.size() == 2 and (parts[0].strip_edges().begins_with("zz_") or RANGES.has(parts[0].strip_edges()))
		if not known or not parts[1].strip_edges().is_valid_float():
			errors.append("cap_overrides entry '%s' is not <capped cvar>=<number>" % entry)
			continue
		out[parts[0].strip_edges()] = parts[1].strip_edges().to_float()
	return out


## The highest [param cvar] accepts under [param overrides]: INF when unlimited, or when it has no range.
static func highest(cvar: String, overrides: Dictionary, bounds: Array = []) -> float:
	if not RANGES.has(cvar) and bounds.is_empty():
		return INF
	var base: Array = RANGES[cvar] if RANGES.has(cvar) else bounds
	var hi: float = float(overrides[cvar]) if overrides.has(cvar) else float(base[1])
	return INF if hi <= 0.0 else hi


## Empty when [param value] is allowed for [param cvar], else the refusal to log.
static func refusal(cvar: String, value: float, overrides: Dictionary, range_of: Array = []) -> String:
	if not RANGES.has(cvar) and range_of.is_empty():
		return ""
	var bounds: Array = RANGES[cvar] if RANGES.has(cvar) else range_of
	var lo := float(bounds[0])
	var hi := highest(cvar, overrides, bounds)
	if is_nan(value) or value < lo:
		return "%s refuses %s: the lowest it takes is %s" % [cvar, value, lo]
	if value > hi:
		return "%s refuses %s: the highest it takes is %s (set cap_overrides \"%s=0\" for no limit)" % [cvar, value, hi, cvar]
	return ""


## The cvars that come in a low/high pair: cvar -> [the config field of its partner, the partner's cvar, whether this one is the low end].
## The old setters clamped a low end to the high one and back, silently; now a value that would cross is REFUSED.
const PAIRS := {
	"zz_mob_min": ["mob_interval_max", "zz_mob_max", true], "zz_mob_max": ["mob_interval_min", "zz_mob_min", false],
	"zz_special_min": ["special_interval_max", "zz_special_max", true], "zz_special_max": ["special_interval_min", "zz_special_min", false],
	"zz_brute_min": ["brute_interval_max", "zz_brute_max", true], "zz_brute_max": ["brute_interval_min", "zz_brute_min", false],
	"zz_respawn_min": ["respawn_max_seconds", "zz_respawn_max", true], "zz_respawn_max": ["respawn_min_seconds", "zz_respawn_min", false],
	"zz_common_speed_base": ["common_speed_max", "zz_common_speed_max", true], "zz_common_speed_max": ["common_speed_base", "zz_common_speed_base", false],
}


## Empty when [param value] keeps [param cvar] on its side of [param partner_value], else the refusal to log, naming the fix.
static func pair_refusal(cvar: String, value: float, partner_value: float) -> String:
	if not PAIRS.has(cvar):
		return ""
	var low: bool = PAIRS[cvar][2]
	var partner: String = PAIRS[cvar][1]
	if low and value > partner_value:
		return "%s refuses %s: it is over %s (%s); raise %s first" % [cvar, value, partner, partner_value, partner]
	if not low and value < partner_value:
		return "%s refuses %s: it is under %s (%s); lower %s first" % [cvar, value, partner, partner_value, partner]
	return ""
