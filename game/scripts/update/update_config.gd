

class_name UpdateConfig
extends RefCounted

const DIR := "user://update"
const CURRENT_PCK := DIR + "/current.pck"
const CURRENT_JSON := DIR + "/current.json"
const NEXT_PCK := DIR + "/next.pck"
const STATE := DIR + "/state.json"
const SETTINGS := "user://settings.cfg"


const DEFAULT_URL := "https://pocketra.net/version.json"


const APP_VERSION_FALLBACK := "0.5"


static func ensure_dir() -> void:
	if not DirAccess.dir_exists_absolute(DIR):
		DirAccess.make_dir_recursive_absolute(DIR)


static func platform() -> String:
	return AndroidPlugin.platform()


static func set_test_platform(name: String) -> void:
	AndroidPlugin.set_test_platform(name)


static func app_version() -> String:
	var v := str(ProjectSettings.get_setting("application/config/version", ""))
	return v if v != "" else APP_VERSION_FALLBACK


static func extension_version() -> String:
	return str(UpdateBoot.extension_version)


static func pack_version() -> int:
	return int(installed_info().get("pack_version", 0))


static func pack_label() -> String:
	return str(installed_info().get("pack_label", ""))


static func installed_info() -> Dictionary:
	return read_json(CURRENT_JSON)


static func version_summary() -> String:
	var pv := pack_version()
	var lbl := pack_label()


	var content := str(pv) if pv > 0 else str(TranslationServer.translate("update.pack_bundled"))
	if pv > 0 and lbl != "":
		content += " (%s)" % lbl


	return "%s · %s" % [str(TranslationServer.translate("update.versions")) % [app_version(), content],
			edition_name(full_edition())]


static func cmp_version(a: String, b: String) -> int:
	return UpdateBoot.cmp_version(a, b)


static func full_edition() -> bool:
	return ContentManager.dev_bundled()


static func edition_name(full: bool) -> String:
	return str(TranslationServer.translate("update.edition_full" if full else "update.edition_dist"))


static func edition_label(full: bool, size: int) -> String:
	if size <= 0:
		return edition_name(full)
	return "%s (%d MB)" % [edition_name(full), int(round(float(size) / 1e6))]


static func apk_choice(info: Dictionary) -> Dictionary:
	var full := full_edition()
	var url := str(info.get("apk_url", ""))
	var size := int(info.get("apk_size", 0))
	var full_url := str(info.get("apk_url_full", ""))
	if full and full_url != "":
		url = full_url
		size = int(info.get("apk_size_full", 0))
	elif full:
		full = false
	return {"url": url, "size": size, "full": full, "label": edition_label(full, size)}


static func app_choice(info: Dictionary) -> Dictionary:
	match platform():
		"iOS":
			var iu := str(info.get("ios_url", ""))
			return {"url": iu, "size": 0, "full": full_edition(), "kind": "ios",
					"label": str(TranslationServer.translate("update.edition_ios")) if iu != "" else ""}
		"Windows":
			var wu := str(info.get("windows_url", ""))
			var ws := int(info.get("windows_size", 0))
			if wu != "":
				var lbl := str(TranslationServer.translate("update.edition_windows"))
				if ws > 0:
					lbl += " (%d MB)" % int(round(float(ws) / 1e6))
				return {"url": wu, "size": ws, "full": true, "kind": "windows", "label": lbl}
		"macOS":


			var mu := str(info.get("mac_url", ""))
			var ms := int(info.get("mac_size", 0))
			if mu != "":
				var lbl := str(TranslationServer.translate("update.edition_macos"))
				if ms > 0:
					lbl += " (%d MB)" % int(round(float(ms) / 1e6))
				return {"url": mu, "size": ms, "full": true, "kind": "macos", "label": lbl}
	var d := apk_choice(info)
	d["kind"] = "apk"
	return d


static func remote_app_version(info: Dictionary) -> String:
	if platform() == "iOS":
		return str(info.get("ios_version", ""))
	return str(info.get("apk_version", ""))


static func get_app_key() -> String:
	return "update.get_ios" if platform() == "iOS" else "update.get_apk"


static func blocked_default_key() -> String:
	return "update.blocked_ios" if platform() == "iOS" else "update.blocked_default"


const PACK_DEFAULT_OFF_ON_IOS := true


static func pack_enabled() -> bool:
	var args := OS.get_cmdline_user_args()
	var k := args.find("--update-pack")
	if k >= 0 and k + 1 < args.size():
		return args[k + 1] == "on"
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) == OK:


		if cfg.has_section_key("update", "pack"):
			return bool(cfg.get_value("update", "pack", false))
	return not (PACK_DEFAULT_OFF_ON_IOS and platform() == "iOS")


static func set_pack_enabled(on: bool) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value("update", "pack", on)
	cfg.save(SETTINGS)


static func check_enabled() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) == OK:
		return bool(cfg.get_value("update", "check_on_start", true))
	return true


static func set_check_enabled(on: bool) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value("update", "check_on_start", on)
	cfg.save(SETTINGS)


static func dev_run() -> bool:
	var args := OS.get_cmdline_user_args()
	if args.has("--test-update") or args.has("--update-url"):
		return false
	return OS.has_feature("editor") or not OS.has_feature("template")


static func url() -> String:
	var args := OS.get_cmdline_user_args()
	var k := args.find("--update-url")
	if k >= 0 and k + 1 < args.size():
		return args[k + 1]
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) == OK:
		var u := str(cfg.get_value("update", "url", ""))
		if u != "":
			return u
	return DEFAULT_URL


static func blocked() -> bool:
	return bool(block_info().get("blocked", false))


static func block_info() -> Dictionary:
	return read_json(STATE)


static func set_blocked(reason: String, notes: String, apk_url: String, apk_label: String = "") -> void:
	ensure_dir()
	write_json(STATE, {
		"blocked": true,
		"reason": reason,
		"notes": notes,
		"apk_url": apk_url,

		"apk_label": apk_label,
		"checked_at": int(Time.get_unix_time_from_system()),


		"apk_seen": apk_seen(),
	})


static func clear_blocked() -> void:
	var seen := apk_seen()
	if seen == "":
		if FileAccess.file_exists(STATE):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(STATE))
		return
	write_json(STATE, {"apk_seen": seen})


static func apk_seen() -> String:
	return str(read_json(STATE).get("apk_seen", ""))


static func set_apk_seen(version: String) -> void:
	var d := read_json(STATE)
	d["apk_seen"] = version
	write_json(STATE, d)


static func app_outdated(remote: String) -> bool:
	if remote.strip_edges() == "":
		return false
	return cmp_version(app_version(), remote) < 0


static func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	return d if d is Dictionary else {}


static func write_json(path: String, data: Dictionary) -> void:
	ensure_dir()
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data, "  "))
		f.close()


const AndroidPlugin := preload("res://scripts/android_plugin.gd")
const ANDROID_PLUGIN := AndroidPlugin.SINGLETON


static func android_restart_plugin() -> Object:
	if OS.get_name() != "Android":
		return null
	return AndroidPlugin.plugin_with(&"restartApp")


static func restart_supported() -> bool:
	if android_restart_plugin() != null:
		return true
	return ["macOS", "Windows", "Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD"].has(OS.get_name())


static func restart(tree: SceneTree) -> void:
	var p := android_restart_plugin()
	if p != null:


		if bool(p.restartApp()):
			return
	if restart_supported():
		OS.set_restart_on_exit(true)
	tree.quit()
