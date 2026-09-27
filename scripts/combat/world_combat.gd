extends Node
## COMBAT-WORLD-01B (D-087): the sandbox encounter with painted effects, in the world:
## one wolf by the trail to the forest inn, past the village. The hero keeps the accepted
## D-059 poses (stance, attack) and shows the courtyard's whole-character guard and hit poses
## (fist-defense, trained) while blocking and when hit, with the painted effects on top.
## The combat code asks its owner for `level` (here the player rig: HUD, CameraRig,
## InventoryMenu, Player) and `technique`.
const SessionScript = preload("res://scripts/combat/painted_combat_session.gd")
const ToolbarScript = preload("res://scripts/combat/world_block_toolbar.gd")
## Village frame; 55 m past the north-east exit, beside the trail, slope about 5 degrees.
const WOLF_HOME := Vector3(130.0, 0.0, -143.7)
## Owner: not in the middle of the road; the wolf waits this far from the trail's centre line.
const WOLF_OFF_TRAIL := 7.0

## QUEST-WOLVES-01 (D-092): wolves run off after this many stuns (trial number).
const FLEE_HITS := 3
## The pack behind the barn (B01, owner: not on the street), in the barn's frame: its gate faces +Z,
## so the wolves stand a few metres past its back wall.
const PACK_BEHIND := [Vector2(-2.5, 4.0), Vector2(2.8, 5.5)]

signal pack_driven_off()

var world: Node3D
var pack: Array[Node] = []
var level: Node
var technique := "trained"
var session: Node
var toolbar: CanvasLayer

func configure(scene: Node3D) -> void:
	world = scene
	level = world.rig
	session = SessionScript.new()
	session.name = "Encounter"
	session.hero_start = null
	session.show_home_rings = false
	session.ground_height = ground_at
	session.spawns = [["wolf", _off_trail(WOLF_HOME)]]
	add_child(session)
	session.setup(self, world.player)
	for enemy in session.enemies:
		enemy.flee_after_hits = FLEE_HITS
	world.player.strike_requested.connect(session.hero_strike)
	# The hero's own guard and hit poses (courtyard fist-defense, merged into the world frames).
	world.player.visual_action_source = session
	toolbar = ToolbarScript.new()
	toolbar.name = "BlockControls"
	add_child(toolbar)
	toolbar.setup(self, session)
	_settle_on_ground.call_deferred()

## Colliders reach the physics space after the first physics frame; until then the ray falls
## back to the relief. Put the enemies back home on the real ground once it is there.
func _settle_on_ground() -> void:
	await get_tree().physics_frame
	for enemy in session.enemies:
		if is_instance_valid(enemy) and enemy.state == "idle":
			enemy.reset_home()

## The lesson calls this when the watchman sends the hero to the barn (and on load at that stage).
func spawn_barn_pack() -> Array[Node]:
	if not pack.is_empty():
		return pack
	var barn: Node3D = null
	for building in world.buildings:
		if building.record.id == "B01":
			barn = building
	if barn == null:
		return pack
	for offset in PACK_BEHIND:
		var at: Vector3 = barn.transform * Vector3(offset.x, 0.0, -float(barn.record.depth) * 0.5 - offset.y)
		at.y = ground_at(at.x, at.z)
		var actor: CharacterBody3D = session.spawn_enemy("wolf", at)
		actor.name = "BarnWolf%d" % pack.size()
		actor.flee_after_hits = FLEE_HITS
		actor.fled.connect(_on_pack_wolf_fled)
		pack.append(actor)
	return pack

func pack_left() -> int:
	var left := 0
	for actor in pack:
		if is_instance_valid(actor) and actor.state != "gone":
			left += 1
	return left

func _on_pack_wolf_fled() -> void:
	if pack_left() == 0:
		pack_driven_off.emit()

## The point moved away from the nearest trail point, on its own side, to WOLF_OFF_TRAIL.
func _off_trail(home: Vector3) -> Vector3:
	var trail: PackedVector3Array = world.trail_dressing.trail if world.get("trail_dressing") != null else PackedVector3Array()
	if trail.is_empty():
		return home
	var nearest := trail[0]
	for p in trail:
		if Vector2(p.x - home.x, p.z - home.z).length() < Vector2(nearest.x - home.x, nearest.z - home.z).length():
			nearest = p
	var away := Vector3(home.x - nearest.x, 0, home.z - nearest.z)
	if away.length() < .01:
		away = Vector3(1, 0, 0)
	return nearest + away.normalized() * WOLF_OFF_TRAIL

func wolf() -> Node3D:
	return session.enemies[0] if not session.enemies.is_empty() else null


## The walkable surface under a point: the trail embankment and its shoulders stand up to ~1.3 m
## above the map relief, so the enemy follows the same colliders the hero walks on (layer 1).
func ground_at(x: float, z: float) -> float:
	var space := world.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(Vector3(x, 400.0, z), Vector3(x, -400.0, z), 1)
	var hit := space.intersect_ray(query)
	return hit.position.y if not hit.is_empty() else world.ground_height_local(x, z)
