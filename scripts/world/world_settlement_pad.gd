extends RefCounted
## Fits a detailed settlement into the baked world height grid (D-081, variant A).
## Inside the settlement rectangle the grid takes the settlement's own heights,
## around it a smooth ring of `ring` metres blends back to the original terrain.
## Grid coordinates: vertex (xi, zi) sits at world map point (xi * spacing, zi * spacing).

## Map-space rectangle (x, z, width, depth). Its edges must lie on the grid.
var rect: Rect2
## World height of settlement level 0.
var base_height: float
## Width of the blend ring in metres.
var ring: float
## Callable(local_x: float, local_z: float) -> float, settlement-local heights.
var local_height: Callable
## Map-space point that is the settlement's local origin.
var local_origin: Vector2


func _init(p_rect: Rect2, p_origin: Vector2, p_base: float, p_ring: float, p_height: Callable) -> void:
	rect = p_rect
	local_origin = p_origin
	base_height = p_base
	ring = p_ring
	local_height = p_height


## Settlement height at a map point, in world metres.
func settlement_height(x: float, z: float) -> float:
	return base_height + float(local_height.call(x - local_origin.x, z - local_origin.y))


## Height of the rectangle border as the world grid draws it: exact at grid vertices,
## linear between them. Used by the settlement ground so the seam has no gaps.
func border_height(x: float, z: float, spacing: float) -> float:
	var on_x_edge := is_equal_approx(x, rect.position.x) or is_equal_approx(x, rect.end.x)
	var t: float = z if on_x_edge else x
	var a := floorf(t / spacing + 0.0001) * spacing
	var b := a + spacing
	var f := clampf((t - a) / spacing, 0.0, 1.0)
	if f < 0.0001:
		return settlement_height(x, a) if on_x_edge else settlement_height(a, z)
	var ha := settlement_height(x, a) if on_x_edge else settlement_height(a, z)
	var hb := settlement_height(x, b) if on_x_edge else settlement_height(b, z)
	return lerpf(ha, hb, f)


func is_on_border(x: float, z: float) -> bool:
	var inside_x := x >= rect.position.x - 0.001 and x <= rect.end.x + 0.001
	var inside_z := z >= rect.position.y - 0.001 and z <= rect.end.y + 0.001
	if not (inside_x and inside_z):
		return false
	return is_equal_approx(x, rect.position.x) or is_equal_approx(x, rect.end.x) \
		or is_equal_approx(z, rect.position.y) or is_equal_approx(z, rect.end.y)


func distance_to_rect(x: float, z: float) -> float:
	var dx := maxf(maxf(rect.position.x - x, 0.0), x - rect.end.x)
	var dz := maxf(maxf(rect.position.y - z, 0.0), z - rect.end.y)
	return Vector2(dx, dz).length()


## Returns a copy of `heights` with the settlement pressed in.
func apply(heights: PackedFloat32Array, width: int, spacing: float) -> PackedFloat32Array:
	var result := heights.duplicate()
	var x0 := maxi(0, int(floor((rect.position.x - ring) / spacing)))
	var x1 := mini(width - 1, int(ceil((rect.end.x + ring) / spacing)))
	var z0 := maxi(0, int(floor((rect.position.y - ring) / spacing)))
	var z1 := mini(width - 1, int(ceil((rect.end.y + ring) / spacing)))
	# The ring blends toward the settlement height at the nearest border point,
	# so every side meets its own edge height rather than one flat level.
	for zi in range(z0, z1 + 1):
		for xi in range(x0, x1 + 1):
			var x := xi * spacing
			var z := zi * spacing
			var d := distance_to_rect(x, z)
			if d > ring:
				continue
			var near := Vector2(clampf(x, rect.position.x, rect.end.x), clampf(z, rect.position.y, rect.end.y))
			var target := settlement_height(near.x, near.y)
			var weight := 1.0 - smoothstep(0.0, ring, d)
			var i := zi * width + xi
			result[i] = lerpf(heights[i], target, weight)
	return result


## True when a grid cell (between vertices xi..xi+1, zi..zi+1) is covered by the settlement ground.
func covers_cell(xi: int, zi: int, spacing: float) -> bool:
	var cx := (xi + 0.5) * spacing
	var cz := (zi + 0.5) * spacing
	return rect.has_point(Vector2(cx, cz))
