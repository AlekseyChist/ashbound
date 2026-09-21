@tool
extends SceneTree
## AshBound tool: builds the courtyard environment as editable, serialized scenes.
## Run: godot --headless --script scripts/tools/build_courtyard_environment.gd
## Produces:
##   scenes/courtyard/props/{well,dummy,fence,woodpile,crate}.tscn  (GLB instance wrappers)
##   scenes/courtyard/courtyard_environment.tscn                     (full diorama)

const PROJECT_DIR := "res://"
const PROPS_DIR := "res://scenes/courtyard/props/"
const ENV_PATH := "res://scenes/courtyard/courtyard_environment.tscn"
const GLB_DIR := "res://assets/buildings/ashbound/"
const BUILDINGS_DIR := "res://scenes/buildings/"
const TEX_DIR := "res://assets/textures/PNG/"

# Collider specs: [size Vector3, center Y offset]
const DUMMY_COLLIDER := Vector3(1.25, 1.8, 0.6)
const FENCE_COLLIDER := Vector3(3.14, 1.1, 0.16)
const WOODPILE_COLLIDER := Vector3(2.1, 1.0, 1.4)
const CRATE_COLLIDER := Vector3(0.85, 0.85, 0.85)

var _failures: int = 0


func _initialize() -> void:
	# Defer the build so the SceneTree is fully ready before we touch resources.
	call_deferred("_build")


func _build() -> void:
	print("[AshBound] Building courtyard environment...")
	var ok := true
	ok = _make_prop_wrappers() and ok
	ok = _make_environment() and ok
	if ok and _failures == 0:
		print("ASHBOUND_COURTYARD_ENVIRONMENT_READY")
		quit(0)
	else:
		push_error("[AshBound] Courtyard environment build FAILED (%d failures)." % _failures)
		quit(1)


# ---------------------------------------------------------------------------
# Prop wrappers (GLB instance + simple StaticBody3D collider)
# ---------------------------------------------------------------------------

func _make_prop_wrappers() -> bool:
	var all_ok := true
	all_ok = _save_prop_wrapper("well", "courtyard_well.glb") and all_ok
	all_ok = _save_prop_wrapper("dummy", "courtyard_dummy.glb", DUMMY_COLLIDER, 0.9) and all_ok
	all_ok = _save_prop_wrapper("fence", "courtyard_fence.glb", FENCE_COLLIDER, 0.55) and all_ok
	all_ok = _save_prop_wrapper("woodpile", "courtyard_woodpile.glb", WOODPILE_COLLIDER, 0.5) and all_ok
	all_ok = _save_prop_wrapper("crate", "courtyard_crate.glb", CRATE_COLLIDER, 0.425) and all_ok
	return all_ok


func _save_prop_wrapper(prop_name: String, glb_file: String, collider_size: Vector3 = Vector3.ZERO, collider_y: float = 0.0) -> bool:
	var glb_path := GLB_DIR + glb_file
	if not ResourceLoader.exists(glb_path):
		push_error("[AshBound] Missing GLB asset: %s" % glb_path)
		_failures += 1
		return false

	var root := Node3D.new()
	root.name = "Root"

	# Imported GLB instance (kept as a real instance, materials reused).
	var glb_res: Resource = load(glb_path)
	if glb_res == null or not (glb_res is PackedScene):
		push_error("[AshBound] GLB is not a PackedScene: %s" % glb_path)
		_failures += 1
		root.queue_free()
		return false
	var glb_instance := (glb_res as PackedScene).instantiate() as Node3D
	if glb_instance == null:
		push_error("[AshBound] GLB instantiate failed: %s" % glb_path)
		_failures += 1
		root.queue_free()
		return false
	root.add_child(glb_instance)

	# Simple StaticBody3D collider, layer 1, mask 0.
	var body := StaticBody3D.new()
	body.name = "Collider"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	if prop_name == "well":
		# Cylindrical collider around the well.
		var cyl := CylinderShape3D.new()
		cyl.radius = 1.3
		cyl.height = 2.0
		shape.shape = cyl
		shape.position = Vector3(0.0, 1.0, 0.0)
	else:
		var box := BoxShape3D.new()
		box.size = collider_size
		shape.shape = box
		shape.position = Vector3(0.0, collider_y, 0.0)
	body.add_child(shape)
	root.add_child(body)

	_assign_owners(root, root)
	var saved := _save_scene(root, PROPS_DIR + prop_name + ".tscn")
	root.queue_free()
	if not saved:
		_failures += 1
	return saved


# ---------------------------------------------------------------------------
# Main environment scene
# ---------------------------------------------------------------------------

func _make_environment() -> bool:
	var root := Node3D.new()
	root.name = "CourtyardEnvironment"

	# --- Ground -------------------------------------------------------------
	var ground := Node3D.new()
	ground.name = "Ground"
	ground.add_child(_make_ground_mesh())
	ground.add_child(_make_static_body(_make_box_shape(Vector3(34.0, 0.6, 32.0), Vector3(0.0, -0.3, -1.0))))
	root.add_child(ground)

	# --- Path strips (flat, slightly raised, no curbs) ----------------------
	var paths := Node3D.new()
	paths.name = "Paths"
	paths.add_child(_make_path_strip(Vector3(2.4, 0.024, 19.0), Vector3(-1.0, 0.012, -2.5), _dirt_material()))
	paths.add_child(_make_path_strip(Vector3(11.0, 0.024, 2.4), Vector3(-4.5, 0.012, -4.0), _dirt_material()))
	paths.add_child(_make_path_strip(Vector3(9.0, 0.024, 2.4), Vector3(3.0, 0.012, 3.0), _dirt_material()))
	# Short inn entry path using the stone texture.
	paths.add_child(_make_path_strip(Vector3(2.4, 0.024, 3.0), Vector3(-8.0, 0.012, -5.5), _stone_material()))
	_rename_children(paths, ["LaneGate", "LaneInn", "LaneTraining", "InnPaving"])
	root.add_child(paths)

	# --- Buildings (real instances of existing scenes) ----------------------
	var buildings := Node3D.new()
	buildings.name = "Buildings"
	buildings.add_child(_instance_building("house", Vector3(-8.0, 0.0, -8.0)))
	buildings.add_child(_instance_building("watchtower", Vector3(9.0, 0.0, -8.0)))
	buildings.add_child(_instance_building("gate", Vector3(0.0, 0.0, -12.0)))
	root.add_child(buildings)

	# --- Props (real instances of the wrappers above) -----------------------
	var props := Node3D.new()
	props.name = "Props"
	props.add_child(_instance_prop("well", Vector3(-1.0, 0.0, -0.5)))
	props.add_child(_instance_prop("dummy", Vector3(7.0, 0.0, 3.0)))
	props.add_child(_instance_prop("woodpile", Vector3(-12.0, 0.0, 0.0)))
	var crate_a := _instance_prop("crate", Vector3(-10.5, 0.0, -3.5))
	crate_a.name = "CrateA"
	props.add_child(crate_a)
	var crate_b := _instance_prop("crate", Vector3(-11.4, 0.0, -3.8))
	crate_b.name = "CrateB"
	props.add_child(crate_b)

	# Fence modules: training yard right edge (X=11, Z 1..7, rotated 90 deg)
	var fence_right := _instance_prop("fence", Vector3(11.0, 0.0, 4.0))
	fence_right.rotation_degrees = Vector3(0.0, 90.0, 0.0)
	props.add_child(fence_right)
	# Far bottom edge (Z=7, X=8), leaving wide entry at X~5.
	props.add_child(_instance_prop("fence", Vector3(8.0, 0.0, 7.0)))
	# A few fences at north gate ends (left/right of the gate passage).
	props.add_child(_instance_prop("fence", Vector3(-4.0, 0.0, -12.0)))
	props.add_child(_instance_prop("fence", Vector3(4.0, 0.0, -12.0)))
	_rename_children(props, ["Well", "Dummy", "Woodpile", "CrateA", "CrateB", "FenceEast", "FenceSouth", "FenceGateWest", "FenceGateEast"])
	root.add_child(props)

	# --- Boundaries: visible low rough stone barriers on all 4 sides --------
	var boundaries := Node3D.new()
	boundaries.name = "Boundaries"
	boundaries.add_child(_make_barrier(Vector3(32.0, 1.2, 0.6), Vector3(0.0, 0.6, -16.0)))
	boundaries.add_child(_make_barrier(Vector3(32.0, 1.2, 0.6), Vector3(0.0, 0.6, 14.0)))
	boundaries.add_child(_make_barrier(Vector3(0.6, 1.2, 30.0), Vector3(-16.0, 0.6, -1.0)))
	boundaries.add_child(_make_barrier(Vector3(0.6, 1.2, 30.0), Vector3(16.0, 0.6, -1.0)))
	_rename_children(boundaries, ["North", "South", "West", "East"])
	root.add_child(boundaries)

	# --- Pines: only OUTSIDE the walkable perimeter, behind the north wall --
	var pines := Node3D.new()
	pines.name = "Pines"
	var pine_spots: Array[Vector3] = [
		Vector3(-12.0, 0.0, -19.0), Vector3(-6.0, 0.0, -20.0),
		Vector3(0.0, 0.0, -19.5), Vector3(6.0, 0.0, -20.0),
		Vector3(12.0, 0.0, -19.0), Vector3(-14.0, 0.0, -17.0),
		Vector3(14.0, 0.0, -17.0), Vector3(3.0, 0.0, -21.0),
	]
	for spot in pine_spots:
		pines.add_child(_make_pine(spot))
	root.add_child(pines)

	# --- Lighting -----------------------------------------------------------
	var lighting := Node3D.new()
	lighting.name = "Lighting"
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-55.0, -25.0, 0.0)
	sun.light_energy = 1.1
	sun.light_color = Color(1.0, 0.96, 0.9)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 45.0
	lighting.add_child(sun)

	var inn_light := OmniLight3D.new()
	inn_light.name = "InnLight"
	inn_light.position = Vector3(-8.0, 2.3, -4.5)
	inn_light.light_color = Color(1.0, 0.75, 0.45)
	inn_light.light_energy = 1.5
	inn_light.omni_range = 4.0
	inn_light.shadow_enabled = false
	lighting.add_child(inn_light)

	var env_node := Node3D.new()
	env_node.name = "Environment"
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	# Overcast procedural sky (replaces flat background color).
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.10, 0.13, 0.18)
	sky_mat.sky_horizon_color = Color(0.36, 0.39, 0.42)
	sky_mat.ground_bottom_color = Color(0.10, 0.12, 0.11)
	sky_mat.ground_horizon_color = Color(0.36, 0.39, 0.42)
	sky_mat.sky_curve = 0.2
	sky_mat.sun_angle_max = 4.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.5, 0.6)
	env.ambient_light_energy = 0.6
	# Mild depth fog only (no volumetric fog).
	env.fog_enabled = true
	env.fog_density = 0.015
	env.fog_light_color = Color(0.2, 0.22, 0.27)
	# Readable tonemap, no overexposure.
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	world_env.environment = env
	env_node.add_child(world_env)
	lighting.add_child(env_node)
	root.add_child(lighting)

	# --- Backdrop: decorative depth ring, no gameplay/collisions ------------
	root.add_child(_make_backdrop())

	# --- Markers (empty Node3D for future gameplay actors) ------------------
	var markers := Node3D.new()
	markers.name = "Markers"
	markers.add_child(_make_marker("Spawn", Vector3(-2.0, 0.1, 7.0)))
	markers.add_child(_make_marker("Innkeeper", Vector3(-6.0, 0.0, -3.5)))
	markers.add_child(_make_marker("Watchman", Vector3(8.0, 0.0, 0.0)))
	markers.add_child(_make_marker("Woodpile", Vector3(-12.0, 0.0, 1.0)))
	markers.add_child(_make_marker("Dummy", Vector3(7.0, 0.0, 3.0)))
	root.add_child(markers)

	_assign_owners(root, root)
	var saved := _save_scene(root, ENV_PATH)
	root.queue_free()
	if not saved:
		_failures += 1
	return saved


# ---------------------------------------------------------------------------
# Node builders
# ---------------------------------------------------------------------------

func _make_ground_mesh() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "GroundMesh"
	var box := BoxMesh.new()
	box.size = Vector3(34.0, 0.6, 32.0)
	mi.mesh = box
	mi.position = Vector3(0.0, -0.3, -1.0)
	mi.material_override = _soil_material()
	return mi


func _make_path_strip(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "PathStrip"
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.position = pos
	mi.material_override = mat
	return mi


func _make_barrier(size: Vector3, pos: Vector3) -> Node3D:
	var holder := Node3D.new()
	holder.name = "Barrier"
	holder.position = pos
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = _stone_material(true)
	holder.add_child(mi)
	holder.add_child(_make_static_body(_make_box_shape(size, Vector3.ZERO)))
	return holder


func _make_pine(pos: Vector3) -> Node3D:
	var pine := Node3D.new()
	pine.name = "Pine"
	pine.position = pos
	# Trunk.
	var trunk := MeshInstance3D.new()
	trunk.name = "Trunk"
	var cyl := CylinderMesh.new()
	cyl.radial_segments = 8
	cyl.rings = 1
	cyl.top_radius = 0.12
	cyl.bottom_radius = 0.2
	cyl.height = 1.4
	trunk.mesh = cyl
	trunk.position = Vector3(0.0, 0.7, 0.0)
	trunk.material_override = _pine_trunk_material()
	pine.add_child(trunk)
	# Conical foliage (two stacked cones for a low-poly look).
	var cone1 := MeshInstance3D.new()
	cone1.name = "FoliageLow"
	var c1 := CylinderMesh.new()
	c1.radial_segments = 8
	c1.rings = 1
	c1.top_radius = 0.0
	c1.bottom_radius = 1.1
	c1.height = 2.0
	cone1.mesh = c1
	cone1.position = Vector3(0.0, 2.2, 0.0)
	cone1.material_override = _pine_foliage_material()
	pine.add_child(cone1)
	var cone2 := MeshInstance3D.new()
	cone2.name = "FoliageTop"
	var c2 := CylinderMesh.new()
	c2.radial_segments = 8
	c2.rings = 1
	c2.top_radius = 0.0
	c2.bottom_radius = 0.75
	c2.height = 1.6
	cone2.mesh = c2
	cone2.position = Vector3(0.0, 3.4, 0.0)
	cone2.material_override = _pine_foliage_material()
	pine.add_child(cone2)
	return pine


## Decorative depth backdrop for the eye-level third-person camera.
## Purely visual: no colliders, no gameplay. Deterministic (sin/cos only).
func _make_backdrop() -> Node3D:
	var backdrop := Node3D.new()
	backdrop.name = "Backdrop"

	# Large ground plane extending beyond the courtyard boundary.
	var ground_mi := MeshInstance3D.new()
	ground_mi.name = "BackdropGround"
	var plane := PlaneMesh.new()
	plane.size = Vector2(240.0, 240.0)
	ground_mi.mesh = plane
	ground_mi.position = Vector3(0.0, -0.08, 0.0)
	var soil := _soil_material()
	soil.uv1_scale = Vector3(70.0, 70.0, 70.0)
	ground_mi.material_override = soil
	backdrop.add_child(ground_mi)

	# Ring of ~32 existing pine nodes at deterministic radius 32..45.
	var tree_count := 32
	for i in tree_count:
		var angle := TAU * float(i) / float(tree_count)
		var radius := 32.0 + 13.0 * (0.5 + 0.5 * sin(float(i) * 12.9898))
		var pos := Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		var pine := _make_pine(pos)
		pine.name = "BackdropPine%d" % i
		var scale := 2.0 + 1.5 * (0.5 + 0.5 * sin(float(i) * 78.233))
		pine.scale = Vector3(scale, scale, scale)
		backdrop.add_child(pine)

	# Disable shadows on all backdrop trees (modest render cost).
	for child in backdrop.get_children():
		if not (child is Node3D):
			continue
		var node := child as Node3D
		for mesh_node in _iter_mesh_instances(node):
			mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return backdrop


func _iter_mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		result.append(node as MeshInstance3D)
	for child in node.get_children():
		if child is Node:
			result.append_array(_iter_mesh_instances(child))
	return result


func _make_marker(marker_name: String, pos: Vector3) -> Marker3D:
	var m := Marker3D.new()
	m.name = marker_name
	m.position = pos
	return m


func _make_static_body(shape: CollisionShape3D) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Collider"
	body.collision_layer = 1
	body.collision_mask = 0
	body.add_child(shape)
	return body


func _make_box_shape(size: Vector3, center: Vector3) -> CollisionShape3D:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = center
	return shape


# ---------------------------------------------------------------------------
# Materials
# ---------------------------------------------------------------------------

func _soil_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(TEX_DIR + "floor_ground_dirt.png")
	mat.uv1_scale = Vector3(12.0, 12.0, 12.0)
	mat.albedo_color = Color(0.55, 0.45, 0.35)  # subdued brown tint
	mat.roughness = 0.95
	return mat


func _dirt_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(TEX_DIR + "floor_ground_dirt.png")
	mat.uv1_scale = Vector3(6.0, 6.0, 6.0)
	mat.albedo_color = Color(0.62, 0.52, 0.38)  # muted ochre
	mat.roughness = 0.95
	return mat


func _stone_material(rough: bool = false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	var tex_path := TEX_DIR + "floor_stone.png"
	if ResourceLoader.exists(tex_path):
		mat.albedo_texture = load(tex_path)
		mat.uv1_scale = Vector3(4.0, 4.0, 4.0)
	mat.albedo_color = Color(0.5, 0.5, 0.52)
	mat.roughness = 1.0 if rough else 0.9
	return mat


func _pine_trunk_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.22, 0.15)
	mat.roughness = 1.0
	return mat


func _pine_foliage_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.1, 0.22, 0.12)  # dark green
	mat.roughness = 1.0
	return mat


# ---------------------------------------------------------------------------
# Instancing helpers
# ---------------------------------------------------------------------------

func _instance_building(building_name: String, pos: Vector3) -> Node3D:
	var path := BUILDINGS_DIR + building_name + ".tscn"
	if not ResourceLoader.exists(path):
		push_error("[AshBound] Missing building scene: %s" % path)
		_failures += 1
		return Node3D.new()
	var res: Resource = load(path)
	if res == null or not (res is PackedScene):
		push_error("[AshBound] Not a PackedScene: %s" % path)
		_failures += 1
		return Node3D.new()
	var inst := (res as PackedScene).instantiate() as Node3D
	if inst == null:
		push_error("[AshBound] Building instantiate failed: %s" % path)
		_failures += 1
		return Node3D.new()
	inst.name = building_name.capitalize()
	inst.position = pos
	return inst


func _instance_prop(prop_name: String, pos: Vector3) -> Node3D:
	var path := PROPS_DIR + prop_name + ".tscn"
	if not ResourceLoader.exists(path):
		push_error("[AshBound] Missing prop wrapper: %s" % path)
		_failures += 1
		return Node3D.new()
	var res: Resource = load(path)
	if res == null or not (res is PackedScene):
		push_error("[AshBound] Not a PackedScene: %s" % path)
		_failures += 1
		return Node3D.new()
	var inst := (res as PackedScene).instantiate() as Node3D
	if inst == null:
		push_error("[AshBound] Prop instantiate failed: %s" % path)
		_failures += 1
		return Node3D.new()
	inst.name = prop_name.capitalize()
	inst.position = pos
	return inst


# ---------------------------------------------------------------------------
# Ownership + saving
# ---------------------------------------------------------------------------

## Assigns owner to every constructed descendant of scene_root (not the root
## itself). Imported/instanced subtrees (nonempty scene_file_path) get their
## top node owned by scene_root but are NOT recursed into, so their internal
## authored ownership is preserved.
func _assign_owners(node: Node, scene_root: Node) -> void:
	for child in node.get_children():
		if not (child is Node):
			continue
		child.owner = scene_root
		if (child as Node).scene_file_path.is_empty():
			_assign_owners(child, scene_root)


func _rename_children(parent: Node, names: Array[String]) -> void:
	var children := parent.get_children()
	for i in names.size():
		if i < children.size():
			children[i].name = names[i]


func _save_scene(root_node: Node, path: String) -> bool:
	var dir_path := ProjectSettings.globalize_path(path.get_base_dir())
	if not DirAccess.dir_exists_absolute(dir_path):
		var err: int = DirAccess.make_dir_recursive_absolute(dir_path)
		if err != OK:
			push_error("[AshBound] Failed to create directory %s (err %d)" % [dir_path, err])
			return false
	var packed := PackedScene.new()
	var pack_err: int = packed.pack(root_node)
	if pack_err != OK:
		push_error("[AshBound] PackedScene.pack failed (%d) for %s" % [pack_err, path])
		return false
	var save_err: int = ResourceSaver.save(packed, path)
	if save_err != OK:
		push_error("[AshBound] ResourceSaver.save failed (%d) for %s" % [save_err, path])
		return false
	print("[AshBound] Saved: %s" % path)
	return true
