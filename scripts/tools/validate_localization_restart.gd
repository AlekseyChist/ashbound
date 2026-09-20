## Paired fresh-process persistence check; path must be the dedicated QA file.
extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var path := "res://.tools/localization-restart-qa.cfg"
	if args.size() != 1 or not args[0] in ["write", "read"]:
		quit(2)
		return
	var loc := root.get_node("Localization")
	loc.load_preferences(path, "en_US")
	if args[0] == "write":
		if loc.set_language("ru") != OK:
			quit(1)
			return
		print("ASHBOUND_LOCALIZATION_RESTART_WRITE_OK")
	else:
		if loc.get_preference() != "ru" or loc.get_language() != "ru" or loc.text("UI_LANGUAGE") != "Язык":
			printerr("LOCALIZATION_RESTART_FAIL")
			quit(1)
			return
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		print("ASHBOUND_LOCALIZATION_RESTART_READ_OK")
	quit(0)
