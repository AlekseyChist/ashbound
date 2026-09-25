extends Node
## INN-REST-01: a bed in the forest inn. The innkeeper rents it for the night, the hero sleeps in it
## until the morning. Trial price (owner, 25 Sep): 3 coins a night; the hostess pays 10 for the firewood.
## The rent is kept in user://world_inn.cfg until the campaign save (SAVE-01) takes over.
signal changed()

const SAVE_PATH := "user://world_inn.cfg"
const PRICE := 3
## The rented bed: in the loft right of the stairwell, by the chest with the lantern (inn frame).
const BED := Vector3(3.0, 3.75, -3.2)
const BED_REACH := 1.7
const WAKE_HOUR := 7.0
const FADE := .6

var world: Node3D
var rented := false
var sleeping := false
var save_path := SAVE_PATH
var _veil: ColorRect

func configure(scene: Node3D) -> void:
	world = scene
	var layer := CanvasLayer.new()
	layer.name = "SleepVeil"
	layer.layer = 20
	add_child(layer)
	_veil = ColorRect.new()
	_veil.color = Color(0, 0, 0, 0)
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_veil)
	load_state()

## The prompt the innkeeper offers once he has greeted the hero: rent a bed, or talk while it is rented.
func keeper_prompt() -> String:
	if rented:
		return Localization.text("COURTYARD_ACTION_TALK")
	return Localization.text("INN_ACTION_RENT", {"price": str(PRICE)})

## Rent the bed when the purse allows; the innkeeper answers either way. Returns true when paid.
func rent() -> bool:
	if rented:
		world.hud.show_message("INN_KEEPER_NAME", "INN_KEEPER_BED_YOURS")
		return false
	var inventory: Node = world.get_node("/root/Inventory")
	if not inventory.has_gold(PRICE) or not inventory.remove_gold(PRICE):
		world.hud.show_message("INN_KEEPER_NAME", "INN_KEEPER_BED_NO_MONEY", {"price": str(PRICE)})
		return false
	rented = true
	world.hud.show_message("INN_KEEPER_NAME", "INN_KEEPER_BED_RENTED")
	_changed()
	return true

func bed_position() -> Vector3:
	return world.inn.to_global(BED)

func bed_in_reach() -> bool:
	if not rented or sleeping or world.inn == null or world.player == null:
		return false
	var offset: Vector3 = bed_position() - world.player.global_position
	return Vector2(offset.x, offset.z).length() <= BED_REACH and absf(offset.y) < 1.2

## Darken, move the clock to the next morning, give the bed back, brighten.
func sleep() -> bool:
	if not bed_in_reach():
		return false
	sleeping = true
	world.player.stop_input()
	world.hud.clear_message()
	var tween := create_tween()
	tween.tween_property(_veil, "color:a", 1.0, FADE)
	await tween.finished
	var atmosphere: Node = world.atmosphere
	atmosphere.set_hour(WAKE_HOUR)
	atmosphere.apply_look()
	atmosphere.save_state()
	rented = false
	_changed()
	await get_tree().create_timer(.4, false).timeout
	tween = create_tween()
	tween.tween_property(_veil, "color:a", 0.0, FADE)
	await tween.finished
	sleeping = false
	world.hud.show_message("", "INN_SLEEP_DONE")
	return true

func _changed() -> void:
	save_state()
	changed.emit()

## Switch to another file (checks use their own) and continue from it.
func use_save(path: String) -> void:
	save_path = path
	load_state()

func save_state() -> Error:
	var config := ConfigFile.new()
	config.set_value("inn", "rented", rented)
	return config.save(save_path)

## A missing or damaged file means no bed is rented.
func load_state() -> void:
	rented = false
	var config := ConfigFile.new()
	if config.load(save_path) != OK:
		return
	var value: Variant = config.get_value("inn", "rented", false)
	rented = value is bool and value
