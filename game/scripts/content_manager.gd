

class_name ContentManager
extends RefCounted

const ROOT := "user://content"
const MANIFEST := "user://content/manifest.json"
const MIX_DIR := "user://content/mix"
const ATLAS_DIR := "user://content/atlas"
const SFX_DIR := "user://content/sfx"
const CD_DIR := "user://content/cd"

const FREEWARE_URL := "https://openra.ppmsite.com/ra-quickinstall.zip"
const FREEWARE_SHA1 := "44241f68e69db9511db82cf83c174737ccda300b"

const FREEWARE_LABEL_MB := 13.5

const CD_URLS := {
	"allied": "https://archive.org/download/cnc-red-alert/redalert_allied.iso",
	"soviet": "https://archive.org/download/cnc-red-alert/redalert_soviets.iso",
	"german": "https://archive.org/download/command-conquer-alarmstufe-rot-incl-addon_202202/Image/Alarmstufe%20Rot%20%28Electronic%20Arts%29/Alliierten%20%28EA%29.iso",
}

const CD_MIN_FREE_BYTES := 1500 * 1024 * 1024


const SETTINGS := "user://settings.cfg"


static func disclaimer_accepted() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) != OK:
		return false
	return bool(cfg.get_value("content", "disclaimer_accepted", false))


static func set_disclaimer_accepted(on: bool) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value("content", "disclaimer_accepted", on)
	cfg.save(SETTINGS)


static func ensure_dir(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		DirAccess.make_dir_recursive_absolute(path)


static var _manifest_cache = null


static func _load_manifest() -> Dictionary:
	if _manifest_cache != null:
		return _manifest_cache
	var out := {}
	if FileAccess.file_exists(MANIFEST):
		var f := FileAccess.open(MANIFEST, FileAccess.READ)
		if f != null:
			var d = JSON.parse_string(f.get_as_text())
			if d is Dictionary:
				out = d
	_manifest_cache = out
	return out


static func _save_manifest(m: Dictionary) -> void:
	_manifest_cache = m
	ensure_dir(ROOT)
	var f := FileAccess.open(MANIFEST, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(m, "  "))
		f.close()


static func component(name: String) -> Dictionary:
	var v = _load_manifest().get(name, {})
	return v if v is Dictionary else {}


static func set_component(name: String, data: Dictionary) -> void:
	_manifest_cache = null
	var m := _load_manifest()
	m[name] = data
	_save_manifest(m)


static func clear_component(name: String) -> void:
	_manifest_cache = null
	var m := _load_manifest()
	m.erase(name)
	_save_manifest(m)


static func dev_bundled() -> bool:


	if OS.get_cmdline_user_args().has("--force-content-locked"):
		return false
	return FileAccess.file_exists("res://assets/atlas/atlas_temperat.json")


static func available() -> bool:
	if OS.get_cmdline_user_args().has("--force-content-locked"):
		return false
	return dev_bundled() or has_freeware()


static func _verify_files(entries: Array) -> bool:
	if entries.is_empty():
		return false
	for entry in entries:
		var path := str(entry.get("path", ""))
		if path == "":
			return false
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			return false
		var expect := int(entry.get("size", -1))
		if expect >= 0 and int(f.get_length()) != expect:
			return false
	return true


static func has_freeware() -> bool:
	if ContentBackend.available():
		return bool(ContentBackend.content_status(ROOT).get("ready", false))
	var c := component("freeware")
	if not bool(c.get("installed", false)):
		return false
	return _verify_files(c.get("verify_files", []))


static func has_cd(id: String) -> bool:
	return bool(component("cd_" + id).get("installed", false))


static func component_size(name: String) -> int:
	return int(component(name).get("size_bytes", 0))


static func _remove_dir_recursive(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var d := DirAccess.open(path)
	if d == null:
		return
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if f != "." and f != "..":
			var full := path.path_join(f)
			if d.current_is_dir():
				_remove_dir_recursive(full)
			else:
				DirAccess.remove_absolute(full)
		f = d.get_next()
	d.list_dir_end()
	DirAccess.remove_absolute(path)


static func delete_freeware() -> void:
	_remove_dir_recursive(MIX_DIR)
	_remove_dir_recursive(ATLAS_DIR)
	_remove_dir_recursive(SFX_DIR)
	clear_component("freeware")


static func delete_cd(id: String) -> void:
	_remove_dir_recursive(CD_DIR.path_join(id))
	for lang in LANG_CD:
		if str(LANG_CD[lang]) == id:
			_remove_dir_recursive(SFX_DIR.path_join(lang))
	clear_component("cd_" + id)


static func delete_all() -> void:
	_remove_dir_recursive(ROOT)
	_manifest_cache = {}


static func dir_size_bytes(dir: String) -> int:
	var total := 0
	var d := DirAccess.open(dir)
	if d == null:
		return 0
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if f != "." and f != ".." and not d.current_is_dir():
			var fa := FileAccess.open(dir.path_join(f), FileAccess.READ)
			if fa != null:
				total += fa.get_length()
		f = d.get_next()
	d.list_dir_end()
	return total


static func total_size_bytes() -> int:
	return _dir_size_recursive(ROOT)


static func _dir_size_recursive(path: String) -> int:
	var total := 0
	var d := DirAccess.open(path)
	if d == null:
		return 0
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if f != "." and f != "..":
			var full := path.path_join(f)
			if d.current_is_dir():
				total += _dir_size_recursive(full)
			else:
				var fa := FileAccess.open(full, FileAccess.READ)
				if fa != null:
					total += fa.get_length()
		f = d.get_next()
	d.list_dir_end()
	return total


static func is_own_file(abs_path: String) -> bool:
	var base := OS.get_user_data_dir()
	if base == "":
		return false
	return abs_path.begins_with(base)


static func installed_languages() -> Array[String]:
	var out: Array[String] = []
	if has_freeware() or dev_bundled():
		out.append("en")
	for lang in LANG_CD:
		if sfx_lang_count(lang) > 0:
			out.append(lang)
	return out


const LANG_CD := {"de": "german"}


const LANG_STUBS := {"de": ["girlokay", "girlyeah", "guyokay1", "guyyeah1"]}


static func lang_source_dir(lang: String) -> String:
	if not LANG_CD.has(lang):
		return ""
	var d: String = CD_DIR.path_join(str(LANG_CD[lang]))
	return d if DirAccess.dir_exists_absolute(d) else ""


static func sfx_lang_count(lang: String) -> int:
	var d := DirAccess.open(SFX_DIR.path_join(lang))
	if d == null:
		return 0
	var n := 0
	for f in d.get_files():
		if f.ends_with(".wav"):
			n += 1
	return n


static func needs_language_sounds(lang: String) -> bool:
	return lang_source_dir(lang) != "" and sfx_lang_count(lang) == 0


static func build_language_sounds(lang: String, progress: Callable = Callable()) -> int:
	var src := lang_source_dir(lang)
	if src == "" or not ContentBackend.available():
		return 0
	ensure_dir(SFX_DIR.path_join(lang))
	ContentBackend.set_force_english(PackedStringArray(LANG_STUBS.get(lang, [])))
	var ok := ContentBackend.convert_sounds(src, SFX_DIR, PackedStringArray(), lang, progress)


	ContentBackend.set_force_english(PackedStringArray())
	if not ok:
		return 0
	return sfx_lang_count(lang)


static func status_lines() -> Array[String]:
	var out: Array[String] = []
	if dev_bundled():
		out.append(_t("content.dev_bundled"))
	else:
		out.append("%s: %s" % [_t("content.freeware_title"),
			(_t("content.installed") % format_mb(component_size("freeware"))) if has_freeware() else _t("content.not_installed")])
	for pair in [["allied", "content.cd_allied"], ["soviet", "content.cd_soviet"], ["german", "content.cd_german"]]:
		var id: String = pair[0]
		out.append("%s: %s" % [_t(pair[1]),
			(_t("content.installed") % format_mb(component_size("cd_" + id))) if has_cd(id) else _t("content.not_installed")])
	var langs := installed_languages()
	out.append(_t("content.status_langs") % (", ".join(langs) if not langs.is_empty() else "—"))


	for lang in LANG_CD:
		if needs_language_sounds(lang):
			out.append(_t("content.voice_missing"))
	out.append(_t("content.status_total") % format_mb(total_size_bytes()))
	return out


static func sha1_hex(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA1)
	while not f.eof_reached():
		var chunk := f.get_buffer(65536)
		if chunk.size() > 0:
			ctx.update(chunk)
		else:
			break
	f.close()
	return ctx.finish().hex_encode()


static func free_space_bytes(target_dir: String) -> int:
	ensure_dir(target_dir)


	var abs_path := ProjectSettings.globalize_path(target_dir)
	var via_ext := ContentBackend.free_space(abs_path)
	if via_ext > 0:
		return via_ext
	var os_name := OS.get_name()
	if os_name != "macOS" and os_name != "Linux" and os_name != "FreeBSD" and os_name != "Windows":
		return -1
	var output := []
	var code := OS.execute("df", ["-k", abs_path], output, true)
	if code != 0 or output.is_empty():
		return -1
	var text := str(output[0])
	var lines := text.strip_edges().split("\n")
	if lines.size() < 2:
		return -1
	var cols := lines[lines.size() - 1].split(" ", false)

	if cols.size() < 4:
		return -1
	if not cols[3].is_valid_int():
		return -1
	return int(cols[3]) * 1024


static func format_mb(bytes: int) -> String:
	return "%.1f MB" % (float(bytes) / 1048576.0)


static func http_error_text(result: int, code: int) -> String:
	match result:
		HTTPRequest.RESULT_CANT_RESOLVE:
			return _t("content.err_net_resolve")
		HTTPRequest.RESULT_CANT_CONNECT:
			return _t("content.err_net_connect")
		HTTPRequest.RESULT_CONNECTION_ERROR, HTTPRequest.RESULT_CHUNKED_BODY_SIZE_MISMATCH:
			return _t("content.err_net_conn")
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			return _t("content.err_net_tls")
		HTTPRequest.RESULT_NO_RESPONSE:
			return _t("content.err_net_noresp")
		HTTPRequest.RESULT_TIMEOUT:
			return _t("content.err_net_timeout")
		HTTPRequest.RESULT_DOWNLOAD_FILE_WRITE_ERROR, HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED:
			return _t("content.err_net_write")
		HTTPRequest.RESULT_DOWNLOAD_FILE_CANT_OPEN:
			return _t("content.err_net_open")
		HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED:
			return _t("content.err_net_redirect")
	if result != HTTPRequest.RESULT_SUCCESS:
		return _t("content.err_net_other")
	if code == 404:
		return _t("content.err_http_404")
	if code == 403 or code == 401:
		return _t("content.err_http_403")
	if code >= 500:
		return _t("content.err_http_5xx") % code
	return _t("content.err_http_other") % code


static func _t(key: String) -> String:
	return String(TranslationServer.translate(key))
