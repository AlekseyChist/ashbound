extends Node
## COMBAT-WORLD-01B (D-087): the sandbox encounter with painted effects, in the world:
## one wolf by the trail to the forest inn, past the village. The hero keeps the accepted
## D-059 poses (stance, attack); block and hit have no poses of their own yet, so the painted
## block effects and the recoil show them until the poses are redrawn.
## The combat code asks its owner for `level` (here the player rig: HUD, CameraRig,
## InventoryMenu, Player) and `technique`.
const SessionScript = preload("res://scripts/combat/painted_combat_session.gd")
const ToolbarScript = preload("res://scripts/combat/world_block_toolbar.gd")
## Village frame; 55 m past the north-east exit, 2 m beside the trail, slope about 5 degrees.
const WOLF_HOME := Vector3(130.0, 0.0, -143.7)

var world: Node3D
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
	session.spawns = [["wolf", WOLF_HOME]]
	add_child(session)
	session.setup(self, world.player)
	world.player.strike_requested.connect(session.hero_strike)
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

func wolf() -> Node3D:
	return session.enemies[0] if not session.enemies.is_empty() else null


## The walkable surface under a point: the trail embankment and its shoulders stand up to ~1.3 m
## above the map relief, so the enemy follows the same colliders the hero walks on (layer 1).
func ground_at(x: float, z: float) -> float:
	var space := world.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(Vector3(x, 400.0, z), Vector3(x, -400.0, z), 1)
	var hit := space.intersect_ray(query)
	return hit.position.y if not hit.is_empty() else world.ground_height_local(x, z)
