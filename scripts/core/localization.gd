extends Node
## Localization autoload: EN/RU via TranslationServer (gettext PO).
## Application settings only (user://settings.cfg), never inventory/quests/saves.

signal language_changed(language: String)

const SETTINGS_PATH := "user://settings.cfg"
const SECTION := "localization"
const KEY_LANGUAGE := "language"
const VALID_PREFERENCES := ["auto", "en", "ru"]

var _preference: String = "auto"
var _effective: String = "en"
var _settings_path: String = SETTINGS_PATH
var _device_locale: String = ""

func _ready() -> void:
	load_preferences()

# ---------------------------------------------------------------------------
# Language resolution
# ---------------------------------------------------------------------------

## Normalize a device locale to a supported language code.
## ru_RU / ru-RU / RU -> "ru", en_GB -> "en", anything else -> "en".
func resolve_language(device_locale: String) -> String:
	var normalized := device_locale.strip_edges().to_lower().replace("-", "_")
	var primary := normalized.get_slice("_", 0)
	if primary == "ru":
		return "ru"
	if primary == "en":
		return "en"
	return "en"

# ---------------------------------------------------------------------------
# Preferences (application settings only)
# ---------------------------------------------------------------------------

## Load saved preference and apply the effective language.
## Never writes settings while reading.
func load_preferences(path: String = SETTINGS_PATH, device_locale: String = "") -> void:
	_settings_path = path
	if device_locale.is_empty():
		_device_locale = OS.get_locale()
	else:
		_device_locale = device_locale

	var preference := "auto"
	var cfg := ConfigFile.new()
	var err := cfg.load(path)
	if err == OK and cfg.has_section(SECTION) and cfg.has_section_key(SECTION, KEY_LANGUAGE):
		var value = cfg.get_value(SECTION, KEY_LANGUAGE)
		if typeof(value) == TYPE_STRING and VALID_PREFERENCES.has(value):
			preference = value
	_preference = preference
	_apply_language()

func get_language() -> String:
	return _effective

## The stored user preference (auto/en/ru), not the resolved language.
func get_preference() -> String:
	return _preference

## Persist a preference and apply it. Only application settings are touched.
func set_language(preference: String) -> Error:
	if not VALID_PREFERENCES.has(preference):
		return ERR_INVALID_PARAMETER

	var cfg := ConfigFile.new()
	var err := cfg.load(_settings_path)
	if err == OK:
		cfg.set_value(SECTION, KEY_LANGUAGE, preference)
	elif err == ERR_FILE_NOT_FOUND:
		cfg = ConfigFile.new()
		cfg.set_value(SECTION, KEY_LANGUAGE, preference)
	else:
		return err

	var save_err := cfg.save(_settings_path)
	if save_err != OK:
		return save_err

	_preference = preference
	_apply_language()
	return OK

# ---------------------------------------------------------------------------
# Applying language to TranslationServer
# ---------------------------------------------------------------------------

func _apply_language() -> void:
	var resolved := "en"
	if _preference == "auto":
		resolved = resolve_language(_device_locale)
	else:
		resolved = _preference
	var previous := _effective
	_effective = resolved
	TranslationServer.set_locale(resolved)
	if resolved != previous:
		language_changed.emit(resolved)

# ---------------------------------------------------------------------------
# Translation helpers
# ---------------------------------------------------------------------------

## Translate a key and substitute named parameters in a single pass.
func text(key: StringName, parameters: Dictionary = {}) -> String:
	var translated := TranslationServer.translate(key)
	return _substitute(translated, parameters)

## Translate a plural form (native gettext forms) and substitute parameters.
## The count argument always wins over any "count" in parameters.
func text_plural(singular: StringName, plural: StringName, count: int, parameters: Dictionary = {}) -> String:
	var translated := TranslationServer.translate_plural(singular, plural, count)
	var params := parameters.duplicate()
	params["count"] = count
	return _substitute(translated, params)

## Single-pass {name} substitution; unknown placeholders are left as-is.
func _substitute(template: String, parameters: Dictionary) -> String:
	if template.is_empty():
		return template
	var result := ""
	var index := 0
	while index < template.length():
		var open_pos := template.find("{", index)
		if open_pos == -1:
			result += template.substr(index)
			break
		result += template.substr(index, open_pos - index)
		var close_pos := template.find("}", open_pos + 1)
		if close_pos == -1:
			result += template.substr(open_pos)
			break
		var name := template.substr(open_pos + 1, close_pos - open_pos - 1)
		if parameters.has(name):
			result += str(parameters[name])
		else:
			result += template.substr(open_pos, close_pos - open_pos + 1)
		index = close_pos + 1
	return result
