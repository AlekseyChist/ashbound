extends "res://scripts/tools/fist_preview_toolbar.gd"


func refresh() -> void:
	super.refresh()
	if _title != null:
		_title.text = Localization.text("ENEMY_PREVIEW_TITLE")
