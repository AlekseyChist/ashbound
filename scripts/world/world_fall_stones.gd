extends Node3D
## WORLD-BUILD-01D: stone on the ledges of the book's falls W2-W5 (build.py FALLS cut each river's
## steepest ~30 m into three drops with pools). At every drop: a boulder on each bank, solid, and
## low stones across the lip that the water breaks on. The edge-rocks boulder (Poly Haven CC0).
const BOULDER := "res://assets/environment/edge-rocks-v1/namaqualand_boulder_02.glb"
## The falls' map points (the book's list, build.py FALLS).
const FALLS := [Vector2(263, 561), Vector2(858, 513), Vector2(1558, 861), Vector2(1412, 640)]
const REACH := 32.0
## A drop: the bed falls faster than this between neighbouring river points.
const DROP_GRADE := 0.6
const MIN_GAP := 4.0

var stones := 0
var solid := 0


func build(world: Node3D) -> void:
	var scene: PackedScene = load(BOULDER)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261015
	var half: float = world.HALF
	for river in world.world_layout.rivers:
		var points: Array = river.world_points
		var widths: Array = river.world_widths
		var last := Vector3.INF
		for i in range(points.size() - 1):
			var p := _v(points[i])
			var q := _v(points[i + 1])
			var near := false
			for f: Vector2 in FALLS:
				if Vector2(p.x, p.z).distance_to(f - Vector2(half, half)) < REACH:
					near = true
			if not near:
				continue
			var run := Vector2(q.x - p.x, q.z - p.z).length()
			if run < 0.05 or (p.y - q.y) / run < DROP_GRADE or p.distance_to(last) < MIN_GAP:
				continue
			last = p
			var along := Vector3(q.x - p.x, 0, q.z - p.z).normalized()
			var side := Vector3(-along.z, 0, along.x)
			var w := float(widths[i]) if i < widths.size() else 4.0
			# the banks: one boulder each side, on the ground at the water's edge, solid
			for s: float in [-1.0, 1.0]:
				var at := p + side * s * (w * 0.5 + rng.randf_range(0.4, 1.2))
				at.y = world.world_ground(at.x, at.z) - 0.25
				_stone(scene, at, rng.randf_range(1.1, 1.8), rng, true)
			# the lip: low stones across, half under the water
			# not an even row (frames: teeth across W4): one to three, scattered, unequal
			var n := clampi(int(w / 2.2), 1, 3) - rng.randi_range(0, 1)
			for k in maxi(n, 1):
				var t := (k + 0.5) / maxi(n, 1) - 0.5 + rng.randf_range(-0.15, 0.15)
				var at := p + side * t * w * 0.8 + along * rng.randf_range(-0.4, 0.6)
				at.y = p.y - 0.15
				_stone(scene, at, rng.randf_range(0.4, 0.95), rng, false)
	print("WORLD_FALL_STONES stones=%d solid=%d" % [stones, solid])


func _v(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


func _stone(scene: PackedScene, at: Vector3, size: float, rng: RandomNumberGenerator, body: bool) -> void:
	var rock: Node3D = scene.instantiate()
	rock.position = at
	rock.rotation.y = rng.randf() * TAU
	rock.scale = Vector3(size, size * rng.randf_range(0.6, 0.85), size)
	add_child(rock)
	stones += 1
	if body:
		var static_body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var cylinder := CylinderShape3D.new()
		cylinder.radius = 0.7 * size
		cylinder.height = 0.9 * size
		shape.shape = cylinder
		static_body.position = at + Vector3.UP * 0.45 * size
		static_body.add_child(shape)
		add_child(static_body)
		solid += 1
