## Independent LOC-01A checks. Never writes the player's settings file.
extends SceneTree

var loc: Node
var failures: Array[String] = []
var events: Array[String] = []
var paths: Array[String] = []
var completed := 0
var serial := 0
var inventory_events := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	loc = root.get_node_or_null("Localization")
	if loc == null:
		printerr("LOCALIZATION_FAIL: missing autoload")
		quit(1)
		return
	for method in ["resolve_language", "load_preferences", "get_language", "get_preference", "set_language", "text", "text_plural"]:
		if not loc.has_method(method):
			printerr("LOCALIZATION_FAIL: missing method " + method)
			quit(1)
			return
	loc.language_changed.connect(func(language: String): events.append(language))
	var inv := root.get_node("Inventory")
	var inventory_before: Dictionary = inv.get_save_data()
	inv.gold_changed.connect(func(_gold: int): inventory_events += 1)
	inv.item_added.connect(func(_item: Dictionary): inventory_events += 1)
	_resolution()
	_startup()
	_persistence_and_events()
	_invalid_preferences()
	_translations_and_parameters()
	_plurals()
	_fallback()
	_fonts_and_state()
	_check(inv.get_save_data() == inventory_before and inventory_events == 0, "language never changes inventory or grants items")
	_check(completed == 8, "all eight groups completed")
	for path in paths:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if failures.is_empty():
		print("ASHBOUND_LOCALIZATION_OK groups=8")
		quit(0)
	else:
		for failure in failures:
			printerr("LOCALIZATION_FAIL: " + failure)
		printerr("ASHBOUND_LOCALIZATION_FAILED failures=%d groups=%d" % [failures.size(), completed])
		quit(1)


func _check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)


func _new_path() -> String:
	serial += 1
	var path := "res://.tools/localization-qa-%d-%d.cfg" % [OS.get_process_id(), serial]
	paths.append(path)
	return path


func _fresh(device: String) -> String:
	var path := _new_path()
	loc.load_preferences(path, device)
	events.clear()
	return path


func _resolution() -> void:
	for input in ["ru", "ru_RU", "ru-RU", "RU", " ru_BY "]:
		_check(loc.resolve_language(input) == "ru", "Russian family " + input)
	for input in ["en", "en_GB", "EN-us", "de_DE", "sr_RS", "", "russian", "rubbish"]:
		_check(loc.resolve_language(input) == "en", "English or fallback " + input)
	completed += 1


func _startup() -> void:
	for device in ["ru_RU", "en_GB", "fr_FR"]:
		var path := _fresh(device)
		var expected := "ru" if device.begins_with("ru") else "en"
		_check(loc.get_preference() == "auto" and loc.get_language() == expected, "fresh startup " + device)
		_check(not FileAccess.file_exists(path), "read does not create preferences")
	for bad in [true, 42, null, "de", "RU", ["ru"]]:
		var path := _new_path()
		var cfg := ConfigFile.new()
		cfg.set_value("localization", "language", bad)
		_check(cfg.save(path) == OK, "prepare bad preference fixture")
		var bytes_before := FileAccess.get_file_as_bytes(path)
		loc.load_preferences(path, "ru_RU")
		_check(loc.get_preference() == "auto" and loc.get_language() == "ru", "invalid stored choice uses device")
		_check(FileAccess.get_file_as_bytes(path) == bytes_before, "reading invalid choice does not rewrite file")
	completed += 1


func _persistence_and_events() -> void:
	var path := _fresh("en_GB")
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "volume", 0.35)
	_check(cfg.save(path) == OK, "prepare unrelated preference")
	_check(loc.set_language("ru") == OK, "select Russian")
	_check(loc.get_language() == "ru" and loc.get_preference() == "ru", "effective and explicit choice")
	_check(events == ["ru"], "one effective-change event")
	_check(cfg.load(path) == OK and cfg.get_value("audio", "volume") == 0.35, "other preferences survive")
	_check(cfg.get_value("localization", "language") == "ru", "choice actually persisted")
	loc.load_preferences(path, "fr_FR")
	_check(loc.get_language() == "ru", "saved choice overrides different device")
	_check(events == ["ru"], "same effective reload is silent")
	_check(loc.set_language("ru") == OK and events == ["ru"], "same selection is silent")
	_check(loc.set_language("auto") == OK, "return to device")
	_check(loc.get_language() == "en" and events == ["ru", "en"], "auto uses device with English fallback")
	_check(loc.set_language("en") == OK and events == ["ru", "en"], "different preference same effective language is silent")
	_check(cfg.load(path) == OK and cfg.get_value("localization", "language") == "en", "explicit same-language choice persists")
	completed += 1


func _invalid_preferences() -> void:
	var path := _fresh("en_US")
	_check(loc.set_language("ru") == OK, "prepare rejection state")
	events.clear()
	var bytes_before := FileAccess.get_file_as_bytes(path)
	for invalid in ["", "de", "RU", "ru_RU", "../ru", " auto "]:
		_check(loc.set_language(invalid) == ERR_INVALID_PARAMETER, "reject unsupported selection " + invalid)
		_check(loc.get_language() == "ru" and loc.get_preference() == "ru" and events.is_empty(), "invalid selection is atomic")
		_check(FileAccess.get_file_as_bytes(path) == bytes_before, "invalid selection does not write")
	var missing_parent := "res://.tools/no-localization-qa-directory-%d/settings.cfg" % OS.get_process_id()
	loc.load_preferences(missing_parent, "ru_RU")
	events.clear()
	_check(loc.set_language("en") != OK, "save failure returned")
	_check(loc.get_language() == "ru" and loc.get_preference() == "auto" and events.is_empty(), "save failure preserves active preference")
	completed += 1


func _translations_and_parameters() -> void:
	_fresh("en_US")
	var expected := {
		"UI_LANGUAGE": ["Language", "Язык"], "UI_LANGUAGE_AUTO": ["System language", "Язык устройства"],
		"UI_CLOSE": ["Close", "Закрыть"], "UI_ACTION_INTERACT": ["Interact", "Действие"],
		"UI_ACTION_ATTACK": ["Attack", "Удар"], "UI_ACTION_RUN": ["Run", "Бег"], "UI_ACTION_WALK": ["Walk", "Ходьба"],
	}
	for language in ["en", "ru"]:
		_check(loc.set_language(language) == OK, "select language for text")
		for key in expected:
			_check(loc.text(key) == expected[key][0 if language == "en" else 1], "catalog text " + language + " " + key)
		var parameters := {"name": "{count}", "count": 42}
		var before := parameters.duplicate(true)
		var greeting := "Hello, {count}." if language == "en" else "Привет, {count}."
		_check(loc.text("UI_GREETING", parameters) == greeting, "literal user name never recursively formatted")
		_check(parameters == before, "text helper preserves parameters")
		_check(str(loc.text("UI_GREETING")).contains("{name}"), "missing parameter remains visible for QA")
		_check(loc.text("UNREGISTERED_KEY") == "UNREGISTERED_KEY", "unknown key deterministic")
	completed += 1


func _plurals() -> void:
	_fresh("ru_RU")
	var counts := [0, 1, 2, 5, 11, 21, 22, 25, 101, 112]
	var russian := ["предметов", "предмет", "предмета", "предметов", "предметов", "предмет", "предмета", "предметов", "предмет", "предметов"]
	for language in ["en", "ru"]:
		_check(loc.set_language(language) == OK, "select for plural")
		for i in range(counts.size()):
			var count: int = counts[i]
			var suffix: String = russian[i] if language == "ru" else ("item" if count == 1 else "items")
			var parameters := {"count": 999}
			_check(loc.text_plural("UI_ITEM_COUNT", "UI_ITEM_COUNTS", count, parameters) == "%d %s" % [count, suffix], "plural %s %d" % [language, count])
			_check(parameters["count"] == 999, "plural helper preserves caller dictionary")
	completed += 1


func _fallback() -> void:
	_fresh("ru_RU")
	var english_only := Translation.new()
	english_only.locale = "en"
	english_only.add_message("QA_ENGLISH_FALLBACK", "English fallback {name}")
	TranslationServer.add_translation(english_only)
	_check(loc.text("QA_ENGLISH_FALLBACK", {"name": "Ada"}) == "English fallback Ada", "missing Russian key falls back to English")
	_check(ProjectSettings.get_setting("internationalization/locale/fallback") == "en", "project declares English fallback")
	TranslationServer.remove_translation(english_only)
	completed += 1


func _fonts_and_state() -> void:
	var font := ThemeDB.fallback_font
	for character in "EnglishРусскийЁё0123456789—«»":
		_check(font.has_char(character.unicode_at(0)), "bundled default font glyph " + character)
	_check(TranslationServer.get_loaded_locales().has("en") and TranslationServer.get_loaded_locales().has("ru"), "both catalogs registered")
	completed += 1
