## Run from an empty QA project, so missing packed resources cannot use source files.
extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1 or not ProjectSettings.load_resource_pack(args[0]):
		printerr("LOCALIZATION_PACK_FAIL: cannot mount pack")
		quit(1)
		return
	var failures: Array[String] = []
	for language in ["en", "ru"]:
		var catalog = load("res://localization/%s.po" % language)
		if not catalog is Translation:
			failures.append("missing packed catalog " + language)
			continue
		TranslationServer.add_translation(catalog)
	var implementation = load("res://scripts/core/localization.gd")
	if not implementation is GDScript:
		failures.append("missing packed language service")
	else:
		var loc: Node = implementation.new()
		for language in ["en", "ru"]:
			loc.load_preferences("user://package-read-only-qa.cfg", language)
			var wanted := "Язык" if language == "ru" else "Language"
			if loc.text("UI_LANGUAGE") != wanted:
				failures.append("packed text " + language)
			wanted = "22 предмета" if language == "ru" else "22 items"
			if loc.text_plural("UI_ITEM_COUNT", "UI_ITEM_COUNTS", 22) != wanted:
				failures.append("packed plural " + language)
		loc.free()
	if failures.is_empty():
		print("ASHBOUND_LOCALIZATION_PACK_OK locales=2")
		quit(0)
	else:
		for failure in failures:
			printerr("LOCALIZATION_PACK_FAIL: " + failure)
		quit(1)
