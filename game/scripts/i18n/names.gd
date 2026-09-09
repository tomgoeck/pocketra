

extends Node

const CSV_PATH := "res://i18n/actor_names_de.csv"

var _de := {}
var _loaded := false


func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var f := FileAccess.open(CSV_PATH, FileAccess.READ)
	if f == null:
		push_warning("Names: %s fehlt" % CSV_PATH)
		return
	f.get_csv_line()
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() >= 2 and row[0] != "":
			_de[row[0]] = row[1]


func of(t: Dictionary) -> String:
	_load()
	var key := str(t.get("name", ""))
	if Lang.is_de() and _de.has(key):
		return _de[key]
	return str(t.get("display_name", key))


func of_key(key: String, fallback: String = "") -> String:
	_load()
	if Lang.is_de() and _de.has(key):
		return _de[key]
	return fallback if fallback != "" else key
