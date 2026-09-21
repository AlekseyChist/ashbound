extends SceneTree

const LEFT_X := -0.90
const RIGHT_X := 0.90
const PLAYER_Y := 0.08
const PLAYER_Z := 10.0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var output := ""
	var view := "side"
	var frame := 3
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			output = arg.trim_prefix("--output=")
		elif arg.begins_with("--view="):
			view = arg.trim_prefix("--view=")
		elif arg.begins_with("--frame="):
			frame = clampi(arg.trim_prefix("--frame=").to_int(), 0, 7)
	if DisplayServer.get_name() == "headless":
		push_error("capture_run_comparison: headless не поддерживается")
		quit(1)
		return
	if output.is_empty():
		push_error("capture_run_comparison: нужен --output=ABS_PATH")
		quit(1)
		return
	root.size = Vector2i(1920, 1080)
	var courtyard_scene: PackedScene = load("res://scenes/courtyard/first_courtyard.tscn")
	var player_scene: PackedScene = load("res://scenes/courtyard/courtyard_player.tscn")
	if courtyard_scene == null or player_scene == null:
		push_error("capture_run_comparison: сцены не найдены")
		quit(1)
		return
	var courtyard: Node = courtyard_scene.instantiate()
	root.add_child(courtyard)
	for i in 3:
		await physics_frame
	var hud := courtyard.get_node_or_null("HUD")
	if hud is CanvasLayer:
		(hud as CanvasLayer).hide()
	var left_player: CharacterBody3D = courtyard.get_node("Actors/Player") as CharacterBody3D
	var right_player: CharacterBody3D = player_scene.instantiate() as CharacterBody3D
	if left_player == null or right_player == null:
		push_error("capture_run_comparison: игроки не найдены")
		quit(1)
		return
	courtyard.add_child(right_player)
	_prepare(left_player, LEFT_X)
	_prepare(right_player, RIGHT_X)
	var rig := courtyard.get_node_or_null("CameraRig")
	if rig is Node:
		(rig as Node).set_process(false)
		(rig as Node).set_physics_process(false)
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 1.6, 15.0)
	root.add_child(cam)
	cam.look_at(Vector3(0.0, 0.95, PLAYER_Z))
	cam.fov = 50.0
	cam.make_current()
	for i in 2:
		await process_frame
	var dir := Vector3.RIGHT
	if view == "back":
		dir = Vector3.FORWARD
	elif view == "front":
		dir = Vector3.BACK
	var ok := _apply_visual(left_player, "walk", dir, frame) and _apply_visual(right_player, "run", dir, frame)
	if not ok:
		push_error("capture_run_comparison: визуал/анимации не готовы")
		quit(1)
		return
	_add_labels()
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var err := img.save_png(output)
	if err != OK:
		push_error("capture_run_comparison: save_png error %d" % err)
		quit(1)
		return
	print("ASHBOUND_RUN_COMPARISON_OK view=%s frame=%d left_pixel_size=%.6f right_pixel_size=%.6f" % [view, frame, _pixel_size(left_player), _pixel_size(right_player)])
	courtyard.queue_free()
	cam.queue_free()
	for i in 2:
		await process_frame
	quit(0)

func _prepare(p: CharacterBody3D, x: float) -> void:
	if p.has_method("stop_input"):
		p.call("stop_input")
	p.input_enabled = false
	p.set_physics_process(false)
	p.position = Vector3(x, PLAYER_Y, PLAYER_Z)

func _apply_visual(p: CharacterBody3D, anim: StringName, dir: Vector3, frame: int) -> bool:
	var component := p.get_node_or_null("Visual")
	if component == null or not component.has_method("update_visual"):
		return false
	component.call("update_visual", anim, dir, 15.0, 15.0)
	var spr := p.get_node_or_null("Visual/Body") as AnimatedSprite3D
	if spr == null:
		return false
	var expected_view := "side"
	if dir == Vector3.FORWARD:
		expected_view = "back"
	elif dir == Vector3.BACK:
		expected_view = "front"
	var expected_anim := anim + "_" + expected_view
	if spr.animation != expected_anim or spr.sprite_frames == null or spr.sprite_frames.get_frame_count(expected_anim) <= frame:
		return false
	spr.pause()
	spr.set_frame_and_progress(frame, 0.0)
	return true

func _pixel_size(p: CharacterBody3D) -> float:
	var visual := p.get_node_or_null("Visual/Body")
	if visual is AnimatedSprite3D:
		return (visual as AnimatedSprite3D).pixel_size
	return -1.0

func _add_labels() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 90
	root.add_child(layer)
	for item in [["Ходьба", 480], ["Бег", 1160]]:
		var label := Label.new()
		label.text = String(item[0])
		label.position = Vector2(float(item[1]), 80.0)
		label.add_theme_font_size_override("font_size", 32)
		label.add_theme_color_override("font_color", Color.WHITE)
		layer.add_child(label)
