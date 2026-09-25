extends "res://scripts/tools/validate_combat_feedback.gd"
## Codex independent UI acceptance; real viewport events, unchanged combat rules.
var tools_bar: Node
var defense_bar: Node
var panel: Control
var toggle: Button
var cam: Node3D
var resets := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not OS.has_feature("android") and DisplayServer.get_name()!="headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1280,720))
		DisplayServer.window_set_position(Vector2i(-10000,-10000))
	get_tree().create_timer(100).timeout.connect(func(): printerr("COMBAT_UI_TIMEOUT"); get_tree().quit(2))
	run.call_deferred()

func button(node_name: String) -> Button:
	return sandbox.find_child(node_name, true, false) as Button

func settle() -> void:
	for i in 3: await get_tree().physics_frame
	# Several physics ticks can precede one rendered frame. Wait for UI _process too.
	for i in 2: await get_tree().process_frame

func center(node_name: String) -> Vector2:
	return button(node_name).get_global_rect().get_center()

func touch(pos: Vector2, down: bool, id: int = 11, canceled: bool = false) -> void:
	var e := InputEventScreenTouch.new()
	e.position=pos; e.index=id; e.pressed=down; e.canceled=canceled
	get_tree().root.push_input(e,true)

func mouse(pos: Vector2, down: bool, device: int = 0, canceled: bool = false) -> void:
	var e := InputEventMouseButton.new()
	e.position=pos; e.global_position=pos; e.pressed=down; e.button_index=MOUSE_BUTTON_LEFT
	e.button_mask=MOUSE_BUTTON_MASK_LEFT if down else 0; e.device=device; e.canceled=canceled
	get_tree().root.push_input(e,true)

func drag(pos: Vector2, id: int, relative: Vector2 = Vector2(120,0)) -> void:
	var e := InputEventScreenDrag.new()
	e.index=id; e.position=pos; e.relative=relative; e.screen_relative=relative
	get_tree().root.push_input(e,true)

func mouse_motion(pos: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.device=0
	e.position=pos; e.global_position=pos; e.relative=Vector2(2,2)
	get_tree().root.push_input(e,true)

func key(code: int, down: bool = true, echo: bool = false) -> void:
	var e := InputEventKey.new()
	e.keycode=code; e.physical_keycode=code; e.pressed=down; e.echo=echo
	get_tree().root.push_input(e,true)

var turn_base := Vector3.ZERO

## The view button is the probe action: reset the camera and remember its rotation.
func reset_turn() -> void:
	cam.reset_view(); await settle()
	turn_base = cam.rotation

func turned() -> bool:
	return not cam.rotation.is_equal_approx(turn_base)

func tap(node_name: String, mode: String = "touch") -> void:
	var pos := center(node_name)
	if mode=="mouse": mouse(pos,true); mouse(pos,false)
	else: touch(pos,true); touch(pos,false)
	await settle()

func set_open(value: bool) -> void:
	if panel.visible!=value: await tap("CombatToolsToggle")
	check(panel.visible==value,"tools visibility "+str(value))

func wake() -> void:
	for n in [tools_bar,defense_bar,player]:
		n.notification(NOTIFICATION_APPLICATION_FOCUS_IN)
		n.notification(NOTIFICATION_WM_WINDOW_FOCUS_IN)
		n.notification(NOTIFICATION_APPLICATION_RESUMED)
	player.input_enabled=true
	await settle()

func capture(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await RenderingServer.frame_post_draw
	var dest := "user://" if OS.has_feature("android") else "res://.tools/"
	check(get_viewport().get_texture().get_image().save_png(dest+"combat-ui-"+label+".png")==OK,"capture "+label)
	var geometry: Dictionary={"viewport":str(get_viewport().get_visible_rect()),"screen":str(DisplayServer.window_get_size())}
	for n in ["CombatToolsToggle","CombatToolsPanel","BackpackButton","ViewButton","GuardButton","DodgeButton","DefenseHintLabel"]:
		var c := sandbox.find_child(n,true,false) as Control
		geometry[n]=str(c.get_global_rect())
	var f := FileAccess.open(dest+"combat-ui-"+label+".json",FileAccess.WRITE)
	f.store_string(JSON.stringify(geometry,"  "))

func run() -> void:
	var loc: Node=get_node("/root/Localization")
	loc.load_preferences("user://combat-ui-qa-language.cfg","ru_RU")
	sandbox=load("res://scripts/tools/combat_dodge_sandbox.tscn").instantiate()
	sandbox.process_mode=Node.PROCESS_MODE_PAUSABLE
	add_child(sandbox); await settle()
	session=sandbox.defense; player=sandbox.level.get_node("Actors/Player")
	wolf=session.enemies[0]; guard=session.enemies[1]
	cam=sandbox.level.get_node("CameraRig")
	tools_bar=sandbox._toolbar; panel=sandbox.find_child("CombatToolsPanel",true,false)
	toggle=button("CombatToolsToggle")
	defense_bar=button("DodgeButton").get_parent().get_parent()
	session.set_physics_process(false)
	for i in 20: await get_tree().physics_frame
	player.set_physics_process(false)
	session.resolved.connect(func(result: String): events.append(result))
	tools_bar.reset_requested.connect(func(): resets+=1)
	await wake()
	check(not panel.visible and toggle.is_visible_in_tree(),"collapsed initial view")
	check(not button("ResetTrialButton").is_visible_in_tree(),"old reset hidden")
	check(not button("NoviceButton").is_visible_in_tree(),"techniques initially hidden")
	var hint: Label=sandbox.find_child("DefenseHintLabel",true,false)
	check(hint.get_global_rect().size.y<=54,"one compact hint row")
	check(not hint.get_global_rect().intersects(toggle.get_global_rect()),"hint does not cover toggle")
	await capture("collapsed-ru")
	group("collapsed view and compact hint")
	var strikes: int=sandbox._strike_count
	var camera_before := cam.rotation
	await tap("CombatToolsToggle")
	check(panel.visible,"touch opens tools")
	check(sandbox._strike_count==strikes and cam.rotation==camera_before,"opening does not attack or rotate")
	if not panel.visible:
		printerr("COMBAT_UI_INCOMPLETE: cannot exercise inaccessible tools"); get_tree().quit(1); return
	await tap("CombatToolsToggle","mouse")
	check(not panel.visible,"real mouse closes tools")
	await tap("CombatToolsToggle","mouse")
	check(panel.visible,"real mouse opens tools")
	group("real mouse and touch toggle exactly once")

	for lang in ["ru","en"]:
		loc.set_language(lang); await settle()
		var attack: Button=sandbox.level.get_node("HUD")._btn_attack
		check(toggle.text==loc.text("COMBAT_TOOLS_CLOSE"),"open title localized "+lang)
		check(get_viewport().get_visible_rect().encloses(panel.get_global_rect()),"panel inside safe viewport")
		check(panel.size.x<=700.1 and panel.size.y<=640.1,"bounded panel size")
		for n in ["CombatToolsTitle","CombatToolsDodgeHint","CombatToolsDefenseHint"]:
			var label := sandbox.find_child(n,true,false) as Label
			check(panel.get_global_rect().encloses(label.get_global_rect()),"instructions inside panel "+n)
			check(label.get_theme_font_size("font_size")>=22 and not label.clip_text,"instructions legible "+n)
		for name in ["CombatToolsToggle","NoviceButton","TrainedButton","ViewButton","ToolsResetButton"]:
			var b := button(name); var rect := b.get_global_rect()
			check(rect.size.x>=260 and rect.size.y>=120,"finger geometry "+name)
			check(b.get_theme_stylebox("normal")==attack.get_theme_stylebox("normal") or b.get_theme_stylebox("normal")==attack.get_theme_stylebox("pressed"),"shared theme "+name)
			check(b.focus_mode==Control.FOCUS_NONE,"no keyboard focus "+name)
			check(b.get_theme_font_size("font_size")>=30,"legible font "+name)
		for other in ["GuardButton","DodgeButton","AttackButton","InventoryButton","Up","Down","Left","Right"]:
			var b := button(other)
			if b!=null: check(not panel.get_global_rect().intersects(b.get_global_rect()),"no battle overlap "+other)
		await capture("expanded-"+lang)
	group("EN/RU, shared HUD styles and touch layout")
	await tap("NoviceButton"); check(sandbox.technique=="novice","novice action")
	await tap("TrainedButton","mouse"); check(sandbox.technique=="trained","trained action")
	# D-057: the backpack button is gone (hidden). The view button is the probe action below:
	# "turned" means exactly one activation happened since the last reset.
	await reset_turn()
	await tap("ViewButton"); check(turned(),"view action once")
	await reset_turn()
	await tap("ViewButton","mouse"); check(turned(),"mouse view once")
	await reset_turn()
	check(not button("BackpackButton").visible,"backpack toggle hidden (D-057)")
	group("all existing equipment and view actions")

	var p := center("ViewButton")
	var outside := panel.get_global_rect().end+Vector2(40,40)
	touch(p,true); drag(p+Vector2(2,2),11,Vector2(2,2)); touch(p,false); await settle()
	check(turned(),"small in-button motion remains a tap")
	await reset_turn()
	touch(p,true); drag(outside,11); drag(p,11); touch(p,false); await settle()
	check(not turned(),"drag away then return cancels tap")
	await reset_turn()
	touch(p,true); touch(outside,false); await settle()
	check(not turned(),"outside release cancels")
	touch(p,true); touch(p,false,11,true); await settle()
	check(not turned(),"canceled UP")
	touch(p,true,11,true); touch(p,false); await settle()
	check(not turned(),"canceled DOWN")
	mouse(p,true,0,true); mouse(p,false); await settle()
	check(not turned(),"canceled mouse DOWN")
	mouse(p,true); mouse_motion(outside); mouse_motion(p); mouse(p,false); await settle()
	check(not turned(),"mouse drag away and back cancels")
	await reset_turn()
	var toggle_pos := center("CombatToolsToggle")
	mouse(toggle_pos,true); mouse_motion(toggle_pos+Vector2(2,0)); mouse(toggle_pos,false); await settle()
	check(not panel.visible,"small mouse motion on toggle is safe")
	await set_open(true)
	group("cancellation and drag ownership")

	await reset_turn()
	touch(p,true,21); touch(p,true,22); touch(p,false,22); await settle()
	check(not turned(),"second finger cannot steal")
	mouse(p,true,InputEvent.DEVICE_ID_EMULATION); mouse(p,false,InputEvent.DEVICE_ID_EMULATION)
	check(not turned(),"emulated click cannot duplicate pending tap")
	touch(p,false,21); await settle()
	check(turned(),"owner completes once")
	await reset_turn()
	await tap("ViewButton"); check(turned(),"ownership freed")
	await reset_turn()
	touch(p,true,0); mouse(p,false); await settle()
	check(not turned(),"real mouse cannot release finger zero")
	touch(p,false,0); await settle()
	check(turned(),"finger zero retains ownership")
	await reset_turn()
	group("second finger and emulated duplicate")

	for notification in [NOTIFICATION_APPLICATION_FOCUS_OUT,NOTIFICATION_WM_WINDOW_FOCUS_OUT,NOTIFICATION_APPLICATION_PAUSED]:
		await set_open(true); await reset_turn(); touch(center("ViewButton"),true)
		tools_bar.notification(notification); await settle()
		check(not panel.visible,"lost focus folds panel "+str(notification))
		key(KEY_F4); key(KEY_F4,false)
		check(not turned(),"inactive shortcut ignored")
		await wake(); touch(p,false); await settle()
		check(not panel.visible and not turned(),"late UP cannot activate")
		check(toggle.text==loc.text("COMBAT_TOOLS_OPEN"),"folded caption restored")
	await set_open(true); await reset_turn(); touch(center("ViewButton"),true)
	get_tree().paused=true; await get_tree().process_frame
	check(not panel.visible,"tree pause folds")
	get_tree().paused=false; await wake(); touch(p,false); await settle()
	check(not turned(),"tree pause clears gesture")
	group("focus, application pause and tree pause")

	await set_open(true); await reset_turn(); touch(center("ViewButton"),true)
	var menu: Node=sandbox.level.get_node("InventoryMenu")
	check(menu.request_open(),"menu begins opening"); await settle()
	check(not panel.is_visible_in_tree() and not toggle.is_visible_in_tree(),"menu hides tools completely")
	key(KEY_F4); key(KEY_F4,false); touch(p,false)
	check(not turned(),"menu ignores tools input")
	menu.close_menu(false); await settle(); await wake()
	check(not panel.visible,"return from menu stays folded")
	group("real menu opening and stale release")

	await set_open(true); p=center("ViewButton"); await set_open(false)
	check(tools_bar._button_index_at(p)==-1 and not tools_bar._point_in_panel(p),"hidden controls excluded from hit test")
	await reset_turn()
	touch(p,true,31); touch(p,false,31); await settle()
	check(not turned(),"hidden button cannot activate")
	# Camera owns only the right 55% of the viewport; the tools panel is on the left.
	var free_world := get_viewport().get_visible_rect().size*Vector2(.55,.5)
	camera_before=cam.rotation
	touch(free_world,true,31); drag(free_world+Vector2(100,0),31); touch(free_world,false,31); await settle()
	check(not cam.rotation.is_equal_approx(camera_before),"folded UI preserves world camera gesture")
	cam.reset_view(); await settle(); await set_open(true)
	var background: Vector2=panel.get_global_rect().position+Vector2(25,25)
	camera_before=cam.rotation
	touch(background,true,32); drag(background+Vector2(30,0),32); touch(background,false,32); await settle()
	check(cam.rotation.is_equal_approx(camera_before),"panel background does not rotate camera")
	group("visible background and hidden rectangle routing")

	await set_open(false)
	key(KEY_F1); key(KEY_F1,false); check(sandbox.technique=="novice","F1 remains available folded")
	key(KEY_F2); key(KEY_F2,false); check(sandbox.technique=="trained","F2 remains available")
	await reset_turn()
	key(KEY_F3); key(KEY_F3,false); check(not turned() and sandbox.technique=="trained","F3 (former backpack) does nothing")
	camera_before=cam.rotation; key(KEY_F4); key(KEY_F4,false)
	check(not cam.rotation.is_equal_approx(camera_before),"F4 view")
	key(KEY_F4,true,true); key(KEY_F4,false); await settle()
	cam.reset_view(); await settle()
	group("existing keyboard shortcuts")

	await set_open(true)
	touch(center("GuardButton"),true,41); check(session.snapshot().guarding,"guard while tools open")
	var before_resets := resets
	await tap("ToolsResetButton","mouse")
	check(resets==before_resets+1 and not session.snapshot().guarding,"reset signal once and clears guard")
	touch(center("GuardButton"),false,41)
	check(defense_bar._guard_source==0,"reset clears owner")
	key(KEY_G); check(session.snapshot().guarding,"G block retained")
	key(KEY_F6); key(KEY_F6,false); key(KEY_G,false)
	check(not session.snapshot().guarding,"F6 reset retained")
	await set_open(false)
	touch(center("Right"),true,45); await tap("CombatToolsToggle")
	check(player._touch_move.x>.5,"opening tools preserves outside movement finger")
	touch(center("Right"),false,45)
	group("reset path, guard and simultaneous movement")

	await set_open(false); reset(); await settle()
	check(hint.text==loc.text("COMBAT_HINT_IDLE"),"idle contextual hint")
	place(guard); player.set_physics_process(true); await settle(); player.set_physics_process(false)
	tick(.1); await settle()
	check(hint.text==loc.text("COMBAT_HINT_WINDUP"),"windup contextual hint")
	until_cue(); await settle()
	check(hint.text==loc.text("COMBAT_HINT_CUE"),"cue hint")
	await capture("cue-en")
	reset(); sandbox.set_technique("novice"); place(guard)
	player.set_physics_process(true); await settle(); player.set_physics_process(false); tick(.1); await settle()
	check(hint.text==loc.text("COMBAT_HINT_NOVICE"),"novice warning only during threat")
	reset(); loc.set_language("ru"); await settle()
	await capture("collapsed-final-ru")
	group("state-dependent hint and actual attack cue")

	if errors.is_empty() and groups==12:
		print("ASHBOUND_COMBAT_UI_OK groups=12"); get_tree().quit(0)
	else:
		printerr("COMBAT_UI_INCOMPLETE groups=%d errors=%d"%[groups,errors.size()]); get_tree().quit(1)
