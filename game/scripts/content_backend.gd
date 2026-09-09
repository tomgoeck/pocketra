

class_name ContentBackend
extends RefCounted

static var _instance = null


static func available() -> bool:
	return ClassDB.class_exists("RaContent")


static func _rc():
	if not available():
		return null
	if _instance == null:
		_instance = ClassDB.instantiate("RaContent")
	return _instance


static func _call(method: String, args: Array, fallback: Variant):
	var rc = _rc()
	if rc == null or not rc.has_method(method):
		push_warning("ContentBackend.%s: RaContent nicht geladen oder Methode fehlt — Bausteinbau übersprungen" % method)
		return fallback
	return rc.callv(method, args)


static func last_error() -> String:
	return str(_call("last_error", [], ""))


static func open_mix(path: String) -> bool:
	return bool(_call("open_mix", [path], false))


static func open_dir(dir: String) -> int:
	return int(_call("open_dir", [dir], 0))


static func build_atlases(mix_dir: String, out_dir: String, progress: Callable = Callable()) -> bool:
	return bool(_call("build_atlases", [mix_dir, out_dir, progress], false))


static func convert_sounds(mix_dir: String, out_dir: String, names: PackedStringArray = [],
		lang: String = "", progress: Callable = Callable()) -> bool:
	return bool(_call("convert_sounds", [mix_dir, out_dir, names, lang, progress], false))


static func set_force_english(names: PackedStringArray) -> void:
	_call("set_force_english", [names], null)


static func iso_extract(iso_path: String, entry: String, out_path: String, progress: Callable = Callable()) -> bool:
	return bool(_call("iso_extract", [iso_path, entry, out_path, progress], false))


static func extract(mix_path: String, name: String, out_path: String) -> bool:
	return bool(_call("extract", [mix_path, name, out_path], false))


static func scan(mix_dir: String) -> Dictionary:
	return _as_dict(_call("scan", [mix_dir], {}))


static func write_manifest(dir: String, extra: Dictionary = {}) -> bool:
	return bool(_call("write_manifest", [dir, extra], false))


static func content_status(dir: String = "user://content") -> Dictionary:
	return _as_dict(_call("content_status", [dir], {}))


static func free_space(path: String) -> int:
	var rc = _rc()
	if rc == null or not rc.has_method("free_space"):
		return -1
	return int(rc.callv("free_space", [path]))


static func _as_dict(v: Variant) -> Dictionary:
	return v if v is Dictionary else {}
