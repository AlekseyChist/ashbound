extends RefCounted


static func all() -> Array[Dictionary]:
	return [
		{
			"id": "H01",
			"title_key": "VILLAGE_HOUSE",
			"scene_path": "res://assets/buildings/forest-village-v1/h01.glb",
			"position": Vector3(-13, 0, 0),
			"entry": Vector3(-1.25, 0.36, 4),
			"width": 6.0,
			"depth": 8.0,
			"floor_height": 0.36,
			"entry_width": 1.15,
		},
		{
			"id": "W01",
			"title_key": "VILLAGE_WORKSHOP",
			"scene_path": "res://assets/buildings/forest-village-v1/w01.glb",
			"position": Vector3(0, 0, 0),
			"entry": Vector3(0.5, 0.36, 4.5),
			"width": 7.0,
			"depth": 9.0,
			"floor_height": 0.36,
			"entry_width": 2.4,
		},
		{
			"id": "B01",
			"title_key": "VILLAGE_BARN",
			"scene_path": "res://assets/buildings/forest-village-v1/b01.glb",
			"position": Vector3(14, 0, 0),
			"entry": Vector3(0, 0.24, 5),
			"width": 8.0,
			"depth": 10.0,
			"floor_height": 0.24,
			"entry_width": 3.0,
		},
	]
