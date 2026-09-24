class_name VillagePropsCatalog
extends RefCounted
## Data-only catalog of village yard props for the three existing buildings.
## Each call to all() returns fresh, independent nested dictionaries.

static func all() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []

	# --- H01 (home) yard ---
	rows.append(_row("home_bench", "H01", "Bench", Vector3(1.2, 0.0, 4.65), deg_to_rad(0.0), 0.78, true, ""))
	rows.append(_row("home_mug", "H01", "Mug", Vector3(1.9, 0.01, 4.65), deg_to_rad(20.0), 1.0, false, "home_bench"))
	rows.append(_row("home_bucket", "H01", "Bucket_Wooden_1", Vector3(3.85, 0.0, 2.55), deg_to_rad(30.0), 1.15, false, ""))
	rows.append(_row("home_apples", "H01", "FarmCrate_Apple", Vector3(-4.15, 0.0, 1.8), deg_to_rad(-12.0), 1.0, false, ""))

	# --- W01 (workshop) yard ---
	rows.append(_row("work_table", "W01", "Workbench", Vector3(4.45, 0.0, -0.2), deg_to_rad(90.0), 1.0, true, ""))
	rows.append(_row("work_mug", "W01", "Mug", Vector3(4.55, 0.01, 0.25), deg_to_rad(25.0), 1.0, false, "work_table"))
	rows.append(_row("work_rope", "W01", "Rope_1", Vector3(4.4, 0.01, -0.65), deg_to_rad(0.0), 0.85, false, "work_table"))
	rows.append(_row("work_anvil", "W01", "Anvil_Log", Vector3(-4.6, 0.0, 1.5), deg_to_rad(20.0), 1.0, true, ""))
	rows.append(_row("work_pickaxe", "W01", "Pickaxe_Bronze", Vector3(3.85, 0.0, -2.0), deg_to_rad(70.0), 1.0, false, ""))

	# --- B01 (barn) yard ---
	rows.append(_row("barn_cart", "B01", "Stall_Cart_Empty", Vector3(-5.45, 0.0, 1.2), deg_to_rad(90.0), 1.0, true, ""))
	rows.append(_row("barn_bag_1", "B01", "Bag", Vector3(5.0, 0.0, -1.5), deg_to_rad(15.0), 1.0, true, ""))
	rows.append(_row("barn_bag_2", "B01", "Bag", Vector3(5.6, 0.0, -0.8), deg_to_rad(-20.0), 0.85, true, ""))
	rows.append(_row("barn_rope", "B01", "Rope_1", Vector3(5.15, 0.0, 0.1), deg_to_rad(45.0), 1.0, false, ""))
	rows.append(_row("barn_apples", "B01", "FarmCrate_Apple", Vector3(-5.45, 0.0, -1.8), deg_to_rad(90.0), 1.0, false, ""))

	return rows


static func _row(id: String, building: String, asset: String, at: Vector3, yaw: float, scale: float, solid: bool, support: String) -> Dictionary:
	return {
		"id": id,
		"building": building,
		"asset": asset,
		"at": at,
		"yaw": yaw,
		"scale": scale,
		"solid": solid,
		"support": support,
	}
