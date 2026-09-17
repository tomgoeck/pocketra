

extends Node

const DIR := "user://update"
const PCK := DIR + "/current.pck"

const INFO := DIR + "/current.json"


var mounted := false
var pack_version := 0
var pack_label := ""

var skip_reason := ""

var extension_version := "0"


static func _migrate_user_dir() -> void:
	if OS.has_feature("editor"):
		return
	var os_name := OS.get_name()
	if os_name != "macOS" and os_name != "Windows" and os_name != "Linux":
		return
	var neu := OS.get_user_data_dir()
	if neu == "" or not neu.get_file().begins_with("pocketra"):
		return
	if FileAccess.file_exists(neu.path_join("settings.cfg")):
		return
	var alt := neu.get_base_dir().path_join("redalert")
	if alt == neu or not DirAccess.dir_exists_absolute(alt):
		return
	var d := DirAccess.open(alt)
	if d == null:
		return
	DirAccess.make_dir_recursive_absolute(neu)
	var verschoben := 0
	for name in d.get_files() + d.get_directories():
		var von := alt.path_join(name)
		var nach := neu.path_join(name)
		if FileAccess.file_exists(nach) or DirAccess.dir_exists_absolute(nach):
			continue
		if DirAccess.rename_absolute(von, nach) == OK:
			verschoben += 1
	print("[UpdateBoot] Nutzerordner uebernommen: %d Eintraege aus %s" % [verschoben, alt])


func _init() -> void:
	_migrate_user_dir()
	extension_version = _read_extension_version()
	var args := OS.get_cmdline_user_args()

	if args.has("--no-update-pack"):
		skip_reason = "--no-update-pack"
		return


	if not (args.has("--test-update") or args.has("--update-url")) \
			and (OS.has_feature("editor") or not OS.has_feature("template")):
		skip_reason = "Entwicklerlauf (kein Export)"
		return


	if not _pack_enabled():
		skip_reason = "Paket auf %s abgeschaltet (Apple 2.5.2, docs/IOS-PAKET.md)" % OS.get_name()
		return
	if not FileAccess.file_exists(PCK):
		return
	var info := _read_json(INFO)
	var need := str(info.get("min_extension", "0"))
	if cmp_version(extension_version, need) < 0:
		skip_reason = "min_extension %s > %s" % [need, extension_version]
		print("Update: Paket übersprungen — braucht Extension ", need, ", vorhanden ", extension_version)
		return
	if ProjectSettings.load_resource_pack(PCK, true):
		mounted = true
		pack_version = int(info.get("pack_version", 0))
		pack_label = str(info.get("pack_label", ""))
		print("Update: Paket ", pack_version, " geladen", (" (%s)" % pack_label) if pack_label != "" else "")
		_reload_translations()
	else:
		skip_reason = "load_resource_pack"
		print("Update: Paket konnte nicht geladen werden — ", PCK)


func _reload_translations() -> void:
	var paths = ProjectSettings.get_setting("internationalization/locale/translations", PackedStringArray())
	if paths == null:
		return
	var n := 0
	for p in paths:
		var path := str(p)


		var old_tr := ResourceLoader.load(path, "Translation", ResourceLoader.CACHE_MODE_REUSE)
		if old_tr is Translation:
			TranslationServer.remove_translation(old_tr)


		var new_tr := ResourceLoader.load(path, "Translation", ResourceLoader.CACHE_MODE_IGNORE)
		if new_tr is Translation:
			TranslationServer.add_translation(new_tr)
			n += 1
		else:
			print("Update: Übersetzung nicht ladbar — ", path)
	print("Update: ", n, " Übersetzung(en) aus dem Paket neu geladen")


static func _pack_enabled() -> bool:
	var args := OS.get_cmdline_user_args()
	var k := args.find("--update-pack")
	if k >= 0 and k + 1 < args.size():
		return args[k + 1] == "on"
	var cfg := ConfigFile.new()
	if cfg.load("user://settings.cfg") == OK:
		var v = cfg.get_value("update", "pack", null)
		if v != null:
			return bool(v)
	var p := OS.get_name()
	var fk := args.find("--force-platform")
	if fk >= 0 and fk + 1 < args.size():
		p = args[fk + 1]
	return p != "iOS"


static func cmp_version(a: String, b: String) -> int:
	var pa := a.strip_edges().split(".")
	var pb := b.strip_edges().split(".")
	for i in maxi(pa.size(), pb.size()):
		var x := int(pa[i]) if i < pa.size() else 0
		var y := int(pb[i]) if i < pb.size() else 0
		if x != y:
			return -1 if x < y else 1
	return 0


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	return d if d is Dictionary else {}


static func _read_extension_version() -> String:
	if not ClassDB.class_exists("RaSim"):
		return "0"
	var o = ClassDB.instantiate("RaSim")
	if o == null or not o.has_method("version"):
		return "0"
	return str(o.call("version"))
