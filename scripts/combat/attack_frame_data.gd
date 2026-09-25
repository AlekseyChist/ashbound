extends Resource
## Attack timing data for a single attack, expressed in frames at TICK_RATE.
## Prototype values; total 1.5s preserved from old 0.8 + 0.7.

const TICK_RATE := 60.0

@export var attack_id: StringName = &"guard_unarmed_v1"
@export var startup_frames: int = 48
@export var active_frames: int = 6
@export var recovery_frames: int = 36
@export var cue_seconds: float = 0.18


func startup_seconds() -> float:
	return float(startup_frames) / TICK_RATE


func active_seconds() -> float:
	return float(active_frames) / TICK_RATE


func recovery_seconds() -> float:
	return float(recovery_frames) / TICK_RATE


func total_seconds() -> float:
	return (float(startup_frames) + float(active_frames) + float(recovery_frames)) / TICK_RATE


func is_valid() -> bool:
	if String(attack_id).is_empty():
		return false
	for frames in [startup_frames, active_frames, recovery_frames]:
		if frames < 1 or frames > 600:
			return false
	if not is_finite(cue_seconds) or cue_seconds <= 0.0:
		return false
	if cue_seconds > startup_seconds():
		return false
	return true


func phase_at(seconds: float) -> String:
	if not is_valid():
		return "invalid"
	if not is_finite(seconds) or seconds < 0.0:
		return "invalid"
	var startup: float = startup_seconds()
	var active_end: float = startup + active_seconds()
	var total: float = total_seconds()
	if seconds < startup:
		return "startup"
	if seconds < active_end:
		return "active"
	if seconds < total:
		return "recovery"
	return "ready"
