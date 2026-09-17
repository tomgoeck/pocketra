

class_name UpdateService
extends Node

const AppLogger := preload("res://scripts/app_logger.gd")


signal status(text: String)

signal update_ready()


signal needs_new_app(apk_url: String, apk_label: String)


signal new_app_available(version: String, notes: String, apk_url: String, apk_label: String)

signal block_changed()


signal finished(outcome: String)

const PHASE_NONE := ""
const PHASE_VERSION := "version"
const PHASE_PACK := "pack"

var _http: HTTPRequest
var _phase := PHASE_NONE
var _info := {}


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.use_threads = true
	_http.timeout = 30.0
	add_child(_http)
	_http.request_completed.connect(_on_completed)


func _process(_dt: float) -> void:
	if _phase != PHASE_PACK or _http == null:
		return
	var total := _http.get_body_size()
	var got := _http.get_downloaded_bytes()
	if total > 0:
		status.emit(tr("update.downloading") % [int(100.0 * float(got) / float(total))])


func busy() -> bool:
	return _phase != PHASE_NONE


func start(force: bool = false) -> void:
	if busy():
		return


	if UpdateConfig.dev_run():
		_log("Update: Prüfung übersprungen — Entwicklerlauf (kein Export)")
		return


	if OS.has_feature("web"):
		_log("Update: Prüfung übersprungen — Browser-Fassung (die Seite ist die Fassung)")
		return
	if not force and not UpdateConfig.check_enabled():
		_log("Update: Prüfung ausgeschaltet")
		return


	if not is_inside_tree():
		_log("Update: Prüfung übersprungen — Menü bereits verlassen")
		return
	var u := UpdateConfig.url()
	_log("Update: frage %s" % u)
	_phase = PHASE_VERSION
	_http.download_file = ""
	var err := _http.request(u)
	if err != OK:
		_fail("request %d" % err)


func _on_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var phase := _phase
	_phase = PHASE_NONE
	if result != HTTPRequest.RESULT_SUCCESS or (code != 200 and code != 0):


		_fail("%s (Ergebnis %d, Code %d)" % [ContentManager.http_error_text(result, code), result, code])
		return
	if phase == PHASE_VERSION:
		_handle_version(body)
	elif phase == PHASE_PACK:
		_handle_pack()


func _handle_version(body: PackedByteArray) -> void:
	var d = JSON.parse_string(body.get_string_from_utf8())
	if not (d is Dictionary):
		_fail("version.json unlesbar")
		return
	_info = d
	var notes := str(_info.get("notes", ""))


	var app := UpdateConfig.app_choice(_info)
	var apk_url := str(app.get("url", ""))
	var apk_label := str(app.get("label", ""))
	_log("Update: Plattform %s (%s), eigene Fassung %s — angeboten wird %s (%s)" % [
			UpdateConfig.platform(), str(app.get("kind", "?")),
			UpdateConfig.edition_name(UpdateConfig.full_edition()),
			apk_label if apk_label != "" else "nichts",
			apk_url if apk_url != "" else "keine URL"])


	if bool(_info.get("disabled", false)):
		_log("Update: Server meldet disabled — Fassung gesperrt")
		UpdateConfig.set_blocked("disabled", notes, apk_url, apk_label)
		block_changed.emit()
		finished.emit("blocked")
		return
	var min_supported := str(_info.get("min_supported", ""))
	var min_pack := int(_info.get("min_supported_pack", 0))
	if (min_supported != "" and UpdateConfig.cmp_version(UpdateConfig.app_version(), min_supported) < 0) \
			or (min_pack > 0 and UpdateConfig.pack_version() < min_pack):
		_log("Update: eigene Fassung (App %s, Paket %d) unter min_supported %s/%d — gesperrt" %
				[UpdateConfig.app_version(), UpdateConfig.pack_version(), min_supported, min_pack])
		UpdateConfig.set_blocked("min_supported", notes, apk_url, apk_label)
		block_changed.emit()
		finished.emit("blocked")
		return

	if UpdateConfig.blocked():
		_log("Update: Sperre aufgehoben")
		UpdateConfig.clear_blocked()
		block_changed.emit()


	var remote_app := UpdateConfig.remote_app_version(_info)
	if UpdateConfig.app_outdated(remote_app):
		_log("Update: Server-App %s, eigene %s — Hinweis auf die neue Fassung (%s)" %
				[remote_app, UpdateConfig.app_version(), str(app.get("kind", "?"))])
		new_app_available.emit(remote_app, notes, apk_url, apk_label)


	if not UpdateConfig.pack_enabled():
		_log("Update: Paket auf %s abgeschaltet — Sperre und Fassungshinweis wurden trotzdem geprüft"
				% UpdateConfig.platform())
		status.emit("")
		finished.emit("pack_off")
		return


	var remote := int(_info.get("pack_version", 0))
	var local := UpdateConfig.pack_version()
	_log("Update: Server-Paket %d, eigenes %d" % [remote, local])
	if remote <= local:
		status.emit(tr("update.uptodate"))
		finished.emit("uptodate")
		return


	var need := str(_info.get("min_extension", "0"))
	if UpdateConfig.cmp_version(UpdateConfig.extension_version(), need) < 0:
		_log("Update: Paket %d braucht Extension %s, vorhanden %s — neue APK nötig" %
				[remote, need, UpdateConfig.extension_version()])
		status.emit(tr("update.need_app"))
		needs_new_app.emit(apk_url, apk_label)
		finished.emit("need_app")
		return

	var url := str(_info.get("pack_url", ""))
	if url == "":
		_fail("pack_url fehlt")
		return
	_start_pack_download(_absolute(url))


func _absolute(u: String) -> String:
	if u.begins_with("http://") or u.begins_with("https://"):
		return u
	return UpdateConfig.url().get_base_dir().path_join(u)


func _start_pack_download(url: String) -> void:
	UpdateConfig.ensure_dir()
	var abs := ProjectSettings.globalize_path(UpdateConfig.NEXT_PCK)
	if FileAccess.file_exists(abs):
		DirAccess.remove_absolute(abs)
	_phase = PHASE_PACK
	_http.download_file = abs
	status.emit(tr("update.downloading") % 0)
	_log("Update: lade %s" % url)
	var err := _http.request(url)
	if err != OK:
		_phase = PHASE_NONE
		_fail("request %d" % err)


func _handle_pack() -> void:
	var abs := ProjectSettings.globalize_path(UpdateConfig.NEXT_PCK)
	var expect := str(_info.get("pack_sha256", "")).to_lower()
	var got := FileAccess.get_sha256(abs).to_lower()
	if expect == "" or got != expect:
		DirAccess.remove_absolute(abs)
		_fail("Prüfsumme falsch (erwartet %s, gelesen %s)" % [expect, got])
		status.emit(tr("update.err_checksum"))
		return
	var cur := ProjectSettings.globalize_path(UpdateConfig.CURRENT_PCK)
	if FileAccess.file_exists(cur):
		DirAccess.remove_absolute(cur)
	if DirAccess.rename_absolute(abs, cur) != OK:
		_fail("Umbenennen next.pck → current.pck fehlgeschlagen")
		return

	UpdateConfig.write_json(UpdateConfig.CURRENT_JSON, {
		"pack_version": int(_info.get("pack_version", 0)),
		"pack_label": str(_info.get("pack_label", "")),
		"pack_sha256": expect,
		"pack_size": int(_info.get("pack_size", 0)),
		"min_extension": str(_info.get("min_extension", "0")),
		"installed_at": int(Time.get_unix_time_from_system()),
	})
	_log("Update: Paket %d bereit (%s)" % [int(_info.get("pack_version", 0)), expect.substr(0, 12)])
	status.emit(tr("update.ready"))
	update_ready.emit()
	finished.emit("ready")


func _fail(reason: String) -> void:
	_phase = PHASE_NONE


	AppLogger.warn("UpdateService", "Prüfung abgebrochen — " + reason)
	status.emit("")
	finished.emit("error")


func _log(text: String) -> void:
	AppLogger.info("UpdateService", text)
