extends CanvasLayer
## DIALOG-CHOICE-01 (owner): answers to choose from in a conversation. The NPC's line on top, one
## large button per answer (touch or mouse), keys 1-9 on a PC, Esc chooses the last (leaving) answer.
## While it is open the hero and the camera wait (the host's is_input_available asks `is_open`).
signal chosen(id: StringName)

const BUTTON_SIZE := Vector2(900, 104)

var world: Node
var panel: PanelContainer
var speaker: Label
var line: Label
var list: VBoxContainer
var _ids: Array[StringName] = []
var is_open := false
## Codex 171: the question over the answers is spoken (D-116) - who asks it, while it is heard.
var _asker := ""


func configure(host: Node) -> void:
	world = host
	layer = 90
	panel = PanelContainer.new()
	panel.theme = preload("res://assets/ui/ashbound_ui.tres")
	panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.offset_bottom = -40.0
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	speaker = Label.new()
	speaker.add_theme_font_size_override("font_size", 28)
	box.add_child(speaker)
	line = Label.new()
	line.add_theme_font_size_override("font_size", 32)
	line.autowrap_mode = TextServer.AUTOWRAP_WORD
	line.custom_minimum_size = Vector2(BUTTON_SIZE.x, 0)
	box.add_child(line)
	list = VBoxContainer.new()
	list.add_theme_constant_override("separation", 10)
	box.add_child(list)
	visible = false


## Opens with the NPC's line and the answers: [[id, text], ...] (text already translated).
func open(speaker_key: String, line_key: String, answers: Array) -> void:
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()
	_ids.clear()
	speaker.text = Localization.text(speaker_key)
	line.text = Localization.text(line_key)
	for n in answers.size():
		var answer: Array = answers[n]
		var button := Button.new()
		button.name = "Answer_%s" % answer[0]
		button.custom_minimum_size = BUTTON_SIZE
		button.text = "%d. %s" % [n + 1, answer[1]]
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", 32)
		button.pressed.connect(choose.bind(StringName(answer[0])))
		list.add_child(button)
		_ids.append(StringName(answer[0]))
	visible = true
	is_open = true
	_asker = speaker_key
	var voice: Node = world.get("voice")
	if voice != null:
		voice.play(line_key, speaker_key)
	if world.has_method("sync_input_state"):
		world.sync_input_state()

## The speaker whose question is being heard now ("" when none).
func speaking() -> String:
	var voice: Node = world.get("voice")
	return _asker if is_open and voice != null and voice.is_speaking() else ""


func choose(id: StringName) -> void:
	if not is_open:
		return
	visible = false
	is_open = false
	# The question stops with the answer; the answer's own line (if any) is spoken next.
	var voice: Node = world.get("voice")
	if voice != null:
		voice.stop()
	_asker = ""
	if world.has_method("sync_input_state"):
		world.sync_input_state()
	chosen.emit(id)


func _input(event: InputEvent) -> void:
	if not is_open or not event is InputEventKey or not event.pressed or event.is_echo():
		return
	var key: int = event.physical_keycode
	if key >= KEY_1 and key <= KEY_9 and key - KEY_1 < _ids.size():
		get_viewport().set_input_as_handled()
		choose(_ids[key - KEY_1])
	elif key == KEY_ESCAPE and not _ids.is_empty():
		get_viewport().set_input_as_handled()
		choose(_ids[-1])
