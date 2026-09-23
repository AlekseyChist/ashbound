extends "res://scripts/tools/validate_combat_ui.gd"
## Codex acceptance from UI Book 1.0, separately from Qwen implementation.
var hud: Node
var run_events := 0
var attack_events := 0

func style_check(b: Button, name_: String, fill: Color, border: Color, width: int) -> void:
	var s := b.get_theme_stylebox(name_) as StyleBoxFlat
	check(s != null, b.name + " flat " + name_)
	if s == null: return
	check(s.bg_color.is_equal_approx(fill), b.name + " fill " + name_)
	check(s.border_color.is_equal_approx(border), b.name + " border " + name_)
	check(s.border_width_left == width and s.border_width_right == width and s.border_width_top == width and s.border_width_bottom == width, b.name + " outline " + name_)
	check(s.corner_radius_top_left == 8 and s.corner_radius_bottom_right == 8, b.name + " radius " + name_)
	if name_ != "focus":
		check(s.content_margin_left == 12 and s.content_margin_right == 12 and s.content_margin_top == 8 and s.content_margin_bottom == 8, b.name + " padding " + name_)

func text_fits(b: Button) -> void:
	var available := b.size - b.get_theme_stylebox("normal").get_minimum_size()
	var measured := b.get_theme_font("font").get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, b.get_theme_font_size("font_size"))
	check(measured.x <= available.x + 1 and measured.y <= available.y + 1, b.name + " complete text " + b.text)

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var dest := "user://" if OS.has_feature("android") else "res://.tools/"
	check(get_viewport().get_texture().get_image().save_png(dest + "ui-book-" + label + ".png") == OK, "capture " + label)
	var geometry: Dictionary = {"viewport": str(get_viewport().get_visible_rect()), "safe": str(defense_bar._root.get_global_rect())}
	for n in ["CombatToolsPanel", "CombatToolsToggle", "GuardButton", "DodgeButton", "AttackButton", "RunButton"]:
		geometry[n] = str((sandbox.find_child(n, true, false) as Control).get_global_rect())
	var f := FileAccess.open(dest + "ui-book-" + label + ".json", FileAccess.WRITE)
	f.store_string(JSON.stringify(geometry, "  "))

func run() -> void:
	var loc: Node = get_node("/root/Localization")
	loc.load_preferences("user://ui-book-qa-language.cfg", "ru_RU")
	sandbox = load("res://scripts/tools/combat_dodge_sandbox.tscn").instantiate()
	sandbox.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(sandbox)
	await settle()
	session = sandbox.defense
	player = sandbox.level.get_node("Actors/Player")
	hud = sandbox.level.get_node("HUD")
	wolf = session.enemies[0]; guard = session.enemies[1]
	tools_bar = sandbox._toolbar
	panel = sandbox.find_child("CombatToolsPanel", true, false)
	toggle = button("CombatToolsToggle")
	defense_bar = button("DodgeButton").get_parent().get_parent()
	cam = sandbox.level.get_node("CameraRig")
	session.set_physics_process(false)
	player.set_physics_process(false)
	hud.run_changed.connect(func(_value: bool): run_events += 1)
	hud.attack_pressed.connect(func(): attack_events += 1)
	await wake()
	reset(); await settle()
	var bronze := Color(0.72, 0.58, 0.32)
	var ivory := Color(0.93, 0.90, 0.84)
	var normal := Color(0.17, 0.18, 0.21, 0.95)
	for n in ["AttackButton", "RunButton", "GuardButton", "DodgeButton", "CombatToolsToggle"]:
		var b := button(n)
		check(b.get_theme_font_size("font_size") == 30, n + " action font 30")
		check(b.get_theme_font("font").resource_path == "res://assets/ui/fonts/OpenSans-SemiBold.ttf", n + " explicit common font")
		check(b.get_theme_font("font").has_char(0x0411) and b.get_theme_font("font").has_char(0x0042), n + " Cyrillic/Latin")
		style_check(b, "normal", normal, bronze, 1)
		style_check(b, "hover", Color(.22,.23,.27,.95), bronze, 1)
		style_check(b, "pressed", Color(.28,.26,.22,1), bronze, 1)
		style_check(b, "disabled", normal, bronze, 1)
		check(b.get_theme_color("font_disabled_color").is_equal_approx(Color("939087")), n + " disabled text")
		check(b.get_theme_color("font_color").is_equal_approx(ivory), n + " body color")
		var focus := b.get_theme_stylebox("focus") as StyleBoxFlat
		check(focus != null and focus.bg_color.a == 0 and focus.border_width_left == 2 and focus.border_color.is_equal_approx(ivory), n + " non-opaque focus ring")
	group("book font, palette, five states")

	for language in ["ru", "en"]:
		loc.set_language(language); await settle()
		var label := "Блок" if language == "ru" else "Block"
		var b := button("GuardButton")
		check(b.text == label and loc.text("DEFENSE_GUARD_NOW") == label, "stable localized block " + language)
		var geometry := b.get_global_rect()
		key(KEY_G); await settle()
		check(session.snapshot().guarding and b.text == label, "held block caption " + language)
		check(b.get_global_rect() == geometry and b.get_theme_font_size("font_size") == 30, "held metrics unchanged")
		style_check(b, "normal", Color(.28,.26,.22,1), bronze, 1)
		await capture("held-" + language)
		key(KEY_G, false); await settle()
		check(not session.snapshot().guarding and b.text == label, "release block " + language)
	group("localized held guard and release")

	for language in ["ru", "en"]:
		reset(); loc.set_language(language); place(guard)
		player.set_physics_process(true); await settle(); player.set_physics_process(false)
		until_cue(); await settle()
		var b := button("GuardButton")
		var rect := b.get_global_rect()
		check(session.is_block_window_open(), "real enemy cue reached")
		check(b.text == ("Блок" if language == "ru" else "Block"), "cue retains label " + language)
		style_check(b, "normal", Color(1,.7,.2), Color(1,.98,.9), 3)
		check(b.get_theme_font_size("font_size") == 30, "cue retains font size")
		await capture("cue-" + language)
		reset(); await settle()
		style_check(b, "normal", normal, bronze, 1)
		check(b.get_global_rect() == rect, "cue/reset retain geometry")
	group("actual attack cue and style restoration")

	for language in ["ru", "en"]:
		loc.set_language(language); await settle()
		hud.reset_controls(); await settle()
		var b := button("RunButton")
		var label := "Бег" if language == "ru" else "Run"
		var rect := b.get_global_rect()
		check(b.text == label and not hud._run_enabled, "run initial label")
		var before := run_events
		await tap("RunButton")
		check(hud._run_enabled and b.button_pressed and b.text == label, "selected run keeps label")
		check(run_events == before + 1 and b.get_global_rect() == rect, "one run event / stable geometry")
		await capture("run-selected-" + language)
		await tap("RunButton")
		check(not hud._run_enabled and not b.button_pressed and b.text == label, "run off state")
	group("selected run stable label and single dispatch")

	for language in ["ru", "en"]:
		loc.set_language(language); await set_open(true)
		var safe: Rect2 = defense_bar._root.get_global_rect()
		check(safe.encloses(panel.get_global_rect()), "tools within safe root " + language)
		var names := ["GuardButton", "DodgeButton", "AttackButton", "RunButton", "CombatToolsToggle", "NoviceButton", "TrainedButton", "BackpackButton", "ViewButton", "ToolsResetButton"]
		for n in names:
			var b := button(n)
			check(b.size.x >= 240 and b.size.y >= 120, n + " logical touch minimum")
			check(b.get_theme_font_size("font_size") == 30, n + " common action role")
			check(safe.encloses(b.get_global_rect()), n + " safe bounds")
			text_fits(b)
		for other in ["GuardButton", "DodgeButton", "AttackButton", "RunButton", "InventoryButton", "Up", "Down", "Left", "Right"]:
			var other_button := button(other)
			# Inventory belongs to the campaign; this isolated combat scene may omit it.
			if other == "InventoryButton" and other_button == null: continue
			check(other_button != null, "required control exists " + other)
			if other_button != null:
				check(not panel.get_global_rect().intersects(other_button.get_global_rect()), "tools do not cover " + other)
		check(not button("GuardButton").get_global_rect().intersects(button("DodgeButton").get_global_rect()), "defense buttons separated")
		for n in ["CombatToolsDodgeHint", "CombatToolsDefenseHint"]:
			var l := sandbox.find_child(n, true, false) as Label
			check(l.get_theme_font_size("font_size") == 22 and panel.get_global_rect().encloses(l.get_global_rect()), n + " readable caption contained")
		await capture("expanded-" + language)
		await set_open(false)
	group("RU/EN text fit, safe area and non-overlapping layout")

	var attack := button("AttackButton")
	attack.disabled = true
	var before := attack_events
	await tap("AttackButton")
	check(attack_events == before, "disabled action emits no attack")
	await capture("disabled")
	attack.disabled = false
	await tap("AttackButton")
	check(attack_events == before + 1, "reenabled action works")
	group("disabled appearance and action gate")

	reset(); await settle()
	touch(center("Up"), true, 81)
	touch(center("GuardButton"), true, 82)
	check(session.snapshot().guarding and player._touch_move.length() > .1, "movement and guard coexist")
	touch(center("GuardButton"), false, 82)
	touch(center("Up"), false, 81)
	check(not session.snapshot().guarding and player._touch_move == Vector2.ZERO, "both fingers release")
	key(KEY_G); await settle()
	defense_bar.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not session.snapshot().guarding, "focus loss clears held guard")
	await wake(); key(KEY_G, false)
	group("multi-touch and interruption retained")

	loc.set_language("ru"); reset(); await settle()
	await capture("final")
	sandbox.queue_free(); await settle()
	group("clean scene teardown")
	if groups != 8: errors.append("UI_BOOK_INCOMPLETE groups=" + str(groups))
	if errors.is_empty(): print("ASHBOUND_UI_BOOK_OK groups=8")
	else: printerr("UI_BOOK_FAILED ", errors)
	get_tree().quit(0 if errors.is_empty() else 1)
