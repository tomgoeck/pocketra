

extends Node

const LOG_DIR := "user://logs"
const LOG_PATH := "user://logs/app.log"
const LOG_PREV := "user://logs/app.1.log"

const MAX_BYTES := 256 * 1024

const RING_MAX := 400

var _ring: PackedStringArray = PackedStringArray()
var _mutex := Mutex.new()
var _file: FileAccess = null
var _bytes := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_open_file()
	info("App", "Start — %s, Godot %s, App %s" % [
		OS.get_name(),
		Engine.get_version_info().get("string", "?"),
		str(ProjectSettings.get_setting("application/config/version", "?"))])


func _open_file() -> void:
	if not DirAccess.dir_exists_absolute(LOG_DIR):
		DirAccess.make_dir_recursive_absolute(LOG_DIR)
	var abs := ProjectSettings.globalize_path(LOG_PATH)
	if FileAccess.file_exists(abs):
		var f := FileAccess.open(abs, FileAccess.READ)
		if f != null:
			_bytes = int(f.get_length())


			f.seek(maxi(0, _bytes - 64 * 1024))
			var tail := f.get_as_text()
			f.close()
			for line in tail.split("\n"):
				if line.strip_edges() != "":
					_ring.append(line)
			while _ring.size() > RING_MAX:
				_ring.remove_at(0)
		if _bytes > MAX_BYTES:
			var prev := ProjectSettings.globalize_path(LOG_PREV)
			if FileAccess.file_exists(prev):
				DirAccess.remove_absolute(prev)
			DirAccess.rename_absolute(abs, prev)
			_bytes = 0
	_file = FileAccess.open(abs, FileAccess.READ_WRITE if FileAccess.file_exists(abs) else FileAccess.WRITE)
	if _file != null:
		_file.seek_end()


func info(tag: String, msg: String) -> void:
	_append("I", tag, msg)


func warn(tag: String, msg: String) -> void:
	_append("W", tag, msg)
	push_warning("%s: %s" % [tag, msg])


func error(tag: String, msg: String) -> void:
	_append("E", tag, msg)
	push_error("%s: %s" % [tag, msg])


func _append(level: String, tag: String, msg: String) -> void:
	var stamp := Time.get_datetime_string_from_system(false, true)
	var line := "%s %s %s: %s" % [stamp, level, tag, msg]
	_mutex.lock()
	_ring.append(line)
	while _ring.size() > RING_MAX:
		_ring.remove_at(0)
	if _file != null:
		_file.store_line(line)
		_file.flush()
		_bytes += line.length() + 1
	_mutex.unlock()


	print(line)


func lines(count: int = 200) -> PackedStringArray:
	_mutex.lock()
	var start := maxi(0, _ring.size() - count)
	var out := _ring.slice(start)
	_mutex.unlock()
	return out


func text(count: int = 200) -> String:
	return "\n".join(lines(count))


func path() -> String:
	return ProjectSettings.globalize_path(LOG_PATH)


func clear() -> void:
	_mutex.lock()
	_ring.clear()
	if _file != null:
		_file.close()
		_file = null
	var abs := ProjectSettings.globalize_path(LOG_PATH)
	if FileAccess.file_exists(abs):
		DirAccess.remove_absolute(abs)
	_bytes = 0
	_mutex.unlock()
	_file = FileAccess.open(abs, FileAccess.WRITE)
	info("App", "Protokoll geleert")
