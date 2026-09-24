extends RefCounted

# Isolated data provider for five repeatable weather presets of the forest village.
# Static, dependency-free: no nodes, clocks, shaders, file IO or other runtime state.
#
# Contract:
# - all() returns a fresh Array[Dictionary] on every call; each Dictionary is an
#   independent copy, so caller mutations never affect later calls.
# - Each Dictionary has: id (String), label (String), rain/wind/fog/cloud/wet (float).
# - All intensities are 0..1 except fog, which is Godot exponential density per meter.
# - Order is fixed: clear, rain, wind, fog, storm.

static func all() -> Array[Dictionary]:
	return [
		{
			"id": "clear",
			"label": "VILLAGE_WEATHER_CLEAR",
			"rain": 0.0,
			"wind": 0.15,
			"fog": 0.002,
			"cloud": 0.0,
			"wet": 0.0,
		},
		{
			"id": "rain",
			"label": "VILLAGE_WEATHER_RAIN",
			"rain": 0.65,
			"wind": 0.45,
			"fog": 0.010,
			"cloud": 0.78,
			"wet": 1.0,
		},
		{
			"id": "wind",
			"label": "VILLAGE_WEATHER_WIND",
			"rain": 0.0,
			"wind": 0.95,
			"fog": 0.003,
			"cloud": 0.25,
			"wet": 0.0,
		},
		{
			"id": "fog",
			"label": "VILLAGE_WEATHER_FOG",
			"rain": 0.0,
			"wind": 0.16,
			"fog": 0.034,
			"cloud": 0.70,
			"wet": 0.20,
		},
		{
			"id": "storm",
			"label": "VILLAGE_WEATHER_STORM",
			"rain": 1.0,
			"wind": 1.0,
			"fog": 0.018,
			"cloud": 1.0,
			"wet": 1.0,
		},
	]
