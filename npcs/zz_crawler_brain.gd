extends "zz_special_brain.gd"

## The crawler: a body with no legs, dragging itself along the ground. It goes for whoever is not
## looking, and when it reaches an ankle it holds on.
##
## [codeblock]
## approach   crawl to the victim, from behind when it can
## lunge      the last metre and a half, fast
## grab       holds the victim where they stand and gnaws (pin kind `grab`)
## [/codeblock]
##
## [b]A grab is a pin the victim can fight.[/b] They cannot walk, but they can shoot it, which
## no other pin allows: it is a crawler, and the genre's worst thing about one is that it was
## under your feet. A friend's shove frees them as from any pin. It is slow and low (its
## hitboxes are 0.75 m tall), so the counter is looking down, which a team running from a mob
## does not do.

const LUNGE := &"lunge"
const RECOVER := &"recover"


func _victim_bonus(id: StringName, at: Vector3) -> float:
	var h := horde()
	if h == null:
		return 0.0

	var player = h.game.player_by_id(id)
	if player == null:
		return 0.0

	# Looking away is worth eight metres; a crawler seen coming is a crawler shot.
	var to_me := npc.position() - at
	to_me.y = 0.0
	if to_me.length() > 0.1 and player.aim_direction().dot(to_me.normalized()) < 0.3:
		return -8.0

	return 0.0


func _may_retreat() -> bool:
	# It is too slow to run away; it keeps coming.
	return false


func _special(_delta: float) -> void:
	var b := body()
	var gap := distance_to(victim)
	var reach := tune(&"grab_reach", 1.5)

	match state:
		RECOVER:
			halt()
			b.anim = ZzZombieBody.Anim.CRAWL
			if in_state_for() > 1.2:
				go(APPROACH)
			return
		LUNGE:
			b.anim = ZzZombieBody.Anim.GRAB
			go_to(survivor_at(victim), tune(&"lunge_speed", 4.5), 0.3)

			if gap <= reach:
				var h := horde()
				if h != null and bool(h.call(&"pin", npc, victim, &"grab")):
					halt()
					go(&"holding")
					return

			if in_state_for() > 1.2:
				cool_down(1.5)
				go(RECOVER)
			return

	if cooled_down() and has_reacted() and gap <= reach + 1.6 and survivor_is(victim, &"up"):
		go(LUNGE)
		return

	go_to(survivor_at(victim), npc.def.move_speed, 0.6)
	b.anim = ZzZombieBody.Anim.CRAWL


func _holding(_delta: float) -> void:
	halt()
	body().anim = ZzZombieBody.Anim.GRAB


func pin_released(released: StringName, why: StringName) -> void:
	super(released, why)
	cool_down(tune(&"grab_cooldown", 6.0) if why == &"shoved" else 2.0)
	go(RECOVER)


func _on_staggered(_direction: Vector3) -> void:
	go(RECOVER)
