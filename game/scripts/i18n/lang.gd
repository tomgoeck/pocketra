

extends Node

const SETTINGS := "user://settings.cfg"
const DEFAULT_LOCALE := "en"


func _init() -> void:
	TranslationServer.set_locale(_detect())


func _detect() -> String:
	var args := OS.get_cmdline_user_args()
	var k := args.find("--lang")
	if k >= 0 and k + 1 < args.size() and (args[k + 1] == "de" or args[k + 1] == "en"):
		return args[k + 1]
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) == OK and cfg.has_section_key("general", "language"):
		var v := str(cfg.get_value("general", "language", ""))
		if v == "de" or v == "en":
			return v
	return "de" if OS.get_locale_language() == "de" else DEFAULT_LOCALE


func is_de() -> bool:
	return TranslationServer.get_locale().begins_with("de")


func code() -> String:
	return "de" if is_de() else "en"


func set_language(new_code: String) -> void:
	if new_code != "de" and new_code != "en":
		return
	TranslationServer.set_locale(new_code)
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value("general", "language", new_code)
	cfg.save(SETTINGS)
