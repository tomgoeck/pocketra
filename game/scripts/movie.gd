

class_name Movie
extends CanvasLayer

signal finished

const DIR := "res://assets/video"

var _player: VideoStreamPlayer
var _done := false


static func path(name: String) -> String:
	var base := name.get_basename()
	var original := OriginalContent.video(base)
	if original != "":
		return original
	var localized := "%s/%s/%s.ogv" % [DIR, Lang.code(), base]
	if ResourceLoader.exists(localized):
		return localized
	return "%s/%s.ogv" % [DIR, base]


static func play(host: Node, name: String) -> Movie:
	if host == null or not host.is_inside_tree() or name == "":
		return null
	var vpath := path(name)
	var stream := load_stream(vpath)
	if stream == null:
		print("Video fehlt (übersprungen): ", vpath)
		return null
	print("Video: ", vpath)
	var m := Movie.new()
	m.layer = 128
	host.get_tree().current_scene.add_child(m)
	m._start(stream)
	return m


static func load_stream(vpath: String) -> VideoStream:
	if vpath.begins_with("res://"):
		return load(vpath) if ResourceLoader.exists(vpath) else null
	if not FileAccess.file_exists(vpath):
		return null
	var st := VideoStreamTheora.new()
	st.file = vpath
	return st


func _start(stream: VideoStream) -> void:
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	var box := AspectRatioContainer.new()
	box.ratio = 4.0 / 3.0
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	_player = VideoStreamPlayer.new()
	_player.bus = "Video"
	_player.expand = true
	_player.finished.connect(_finish)
	box.add_child(_player)
	_player.stream = stream
	_player.play()
	MusicPlayer.set_paused(true)


func _input(e: InputEvent) -> void:
	if (e is InputEventScreenTouch and e.pressed) or (e is InputEventMouseButton and e.pressed) \
			or (e is InputEventKey and e.pressed):
		get_viewport().set_input_as_handled()
		_finish()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_finish()


func skip() -> void:
	_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	if _player != null:
		_player.stop()
	MusicPlayer.set_paused(false)
	finished.emit()
	queue_free()
