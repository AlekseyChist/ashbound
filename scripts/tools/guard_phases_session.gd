extends "res://scripts/tools/painted_combat_session.gd"
## Сессия с фазовым guard-актёром: guard получает frame_guard_actor,
## wolf остаётся как в базовой painted_combat_session.

const FRAME_GUARD_ACTOR_PATH := "res://scripts/tools/frame_guard_actor.gd"


func _create_enemy_actor(p_kind: String) -> CharacterBody3D:
	if p_kind == "guard":
		var guard_script: GDScript = load(FRAME_GUARD_ACTOR_PATH)
		return guard_script.new()
	return super._create_enemy_actor(p_kind)


## Вызывается только guard-актёром, когда активное окно закрылось без попадания.
## Публикует ровно один исход (miss или obstructed), hit/block после конца окна запрещены.
func resolve_expired_enemy_attack(actor: CharacterBody3D) -> String:
	if not enabled():
		return "cancelled"
	if actor == null or not is_instance_valid(actor):
		return "cancelled"
	if not enemies.has(actor):
		return "cancelled"
	if actor.kind != "guard":
		return "cancelled"
	if actor.state != "active":
		return "cancelled"
	var active_seconds: float = actor.attack_data.active_seconds()
	if actor.state_time < active_seconds - 1e-8:
		return "cancelled"

	var result: String = enemy_contact_geometry(actor)
	if result == "obstructed":
		result = "obstructed"
	else:
		result = "miss"

	_active_source = actor
	device.global_position = actor.global_position
	_strike_dir = actor.facing_direction
	_contact_done = true
	_publish_enemy_result(result)
	return result


func snapshot() -> Dictionary:
	var snap: Dictionary = super.snapshot()
	for e in enemies:
		if e is Node and is_instance_valid(e):
			if "state" in e and e.state == "active":
				snap["phase"] = "active"
				break
	return snap
