extends Node


const AppLogger := preload("res://scripts/app_logger.gd")
const WebFiles := preload("res://scripts/content/web_files.gd")


signal progress(anteil: float, text: String)

signal finished(erfolg: bool)

const DIR := "user://extras"

const BUNDLES := [
	{"name": "music", "zip": "extras/music.zip", "ziel": DIR + "/music", "probe": "1.mp3"},
	{"name": "maps", "zip": "extras/maps.zip", "ziel": DIR + "/maps", "probe": "index.json"},
]

var _http: HTTPRequest
var _queue: Array = []
var _aktuell := {}
var _laeuft := false


func _ready() -> void:
	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_done)
	set_process(false)


static func aktiv() -> bool:
	return OS.has_feature("web")


static func fehlend() -> Array:
	var out := []
	for b in BUNDLES:
		if not FileAccess.file_exists(str(b["ziel"]).path_join(str(b["probe"]))):
			out.append(b)
	return out


func start() -> void:
	if _laeuft or not aktiv():
		return
	_queue = fehlend()
	if _queue.is_empty():
		finished.emit(true)
		return
	DirAccess.make_dir_recursive_absolute(DIR)
	_laeuft = true
	_next()


func _next() -> void:
	if _queue.is_empty():
		_laeuft = false
		set_process(false)
		progress.emit(1.0, tr("extras.done"))
		finished.emit(true)
		return
	_aktuell = _queue.pop_front()
	var url: String = WebFiles.page_dir_url() + str(_aktuell["zip"])
	AppLogger.info("WebExtras", "lade %s" % url)
	var err := _http.request(url)
	if err != OK:
		_fehler("request() = %d" % err)
		return
	set_process(true)


func _process(_dt: float) -> void:
	var ganz := _http.get_body_size()
	if ganz <= 0:
		return
	var teil := float(_http.get_downloaded_bytes()) / float(ganz)
	progress.emit(clampf(teil, 0.0, 1.0), tr("extras.loading") % [
			str(_aktuell.get("name", "")), roundi(teil * 100.0)])


func _on_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	set_process(false)
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or body.is_empty():
		_fehler("Ergebnis %d, Code %d, %d Byte" % [result, code, body.size()])
		return
	var tmp := DIR.path_join("tmp.zip")
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		_fehler("kann %s nicht schreiben" % tmp)
		return
	f.store_buffer(body)
	f.close()
	var ziel := str(_aktuell["ziel"])
	var anzahl := _entpacken(tmp, ziel)
	DirAccess.remove_absolute(tmp)
	if anzahl <= 0:
		_fehler("Buendel leer oder unlesbar")
		return
	AppLogger.info("WebExtras", "%s: %d Dateien nach %s" % [_aktuell.get("name", ""), anzahl, ziel])
	_next()


func _entpacken(zip_pfad: String, ziel: String) -> int:
	var zip := ZIPReader.new()
	if zip.open(zip_pfad) != OK:
		return 0
	DirAccess.make_dir_recursive_absolute(ziel)
	var n := 0
	for eintrag in zip.get_files():
		if eintrag.ends_with("/"):
			continue
		var daten := zip.read_file(eintrag)
		if daten.is_empty():
			continue
		var out := ziel.path_join(eintrag.get_file())
		var g := FileAccess.open(out, FileAccess.WRITE)
		if g == null:
			continue
		g.store_buffer(daten)
		g.close()
		n += 1
	zip.close()
	return n


func _fehler(grund: String) -> void:
	AppLogger.warn("WebExtras", "%s fehlgeschlagen: %s" % [_aktuell.get("name", "?"), grund])
	_laeuft = false
	set_process(false)


	progress.emit(0.0, tr("extras.failed"))
	finished.emit(false)
