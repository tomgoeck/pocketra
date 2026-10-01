

extends RefCounted

const DIR := "user://replays"

var path := ""
var _f: FileAccess = null
var _frames := 0


func begin(code: String, setup: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(DIR)
	var stamp := Time.get_datetime_string_from_system(false, false).replace(":", "").replace("-", "").replace("T", "-")
	path = "%s/%s-%s.rajson" % [DIR, code if code != "" else "lokal", stamp]
	_f = FileAccess.open(path, FileAccess.WRITE)
	if _f == null:
		path = ""
		return false
	_f.store_line(JSON.stringify({"t": "setup", "code": code, "setup": setup,
			"app": UpdateConfig.app_version(), "started": Time.get_datetime_string_from_system()}))
	_f.flush()
	return true


func frame(f: int, tick: int, packets: Array, hash_text: String = "") -> void:
	if _f == null:
		return
	var line := {"t": "frame", "f": f, "tick": tick, "p": packets}
	if hash_text != "":
		line["hash"] = hash_text
	_f.store_line(JSON.stringify(line))
	_frames += 1

	if _frames % 25 == 0:
		_f.flush()


func local(tick: int, cmd: PackedInt32Array) -> void:
	if _f == null:
		return
	var a: Array = []
	for v in cmd:
		a.append(int(v))
	_f.store_line(JSON.stringify({"t": "cmd", "tick": tick, "c": a}))


func note(text: String) -> void:
	if _f != null:
		_f.store_line(JSON.stringify({"t": "note", "text": text}))
		_f.flush()


func close() -> void:
	if _f != null:
		_f.flush()
		_f = null
