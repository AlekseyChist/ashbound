extends RefCounted
## Trial dimensions, not approved geography or canonical city placement.

static func main_path() -> PackedVector3Array:
	return PackedVector3Array([
		Vector3(0, 0, 0), Vector3(0, 0, -90), Vector3(-45, 1, -160),
		Vector3(-20, 2, -235), Vector3(35, 3, -290), Vector3(35, 3, -315),
		Vector3(35, 3, -333), Vector3(35, 3, -350), Vector3(95, 8, -420),
		Vector3(60, 16, -490), Vector3(20, 22, -550),
	])

static func loop_path() -> PackedVector3Array:
	return PackedVector3Array([
		Vector3(-45, 1, -160), Vector3(-105, 1, -190),
		Vector3(-100, 2, -235), Vector3(-20, 2, -235),
	])

static func length_of(points: PackedVector3Array) -> float:
	var result := 0.0
	for i in range(1, points.size()):
		result += points[i - 1].distance_to(points[i])
	return result
