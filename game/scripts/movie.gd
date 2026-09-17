

class_name Movie
extends CanvasLayer

signal finished

const DIR := "res://assets/video"

var _player: VideoStreamPlayer
var _done := false


var _vqa: VqaPlayer = null
var _vqa_tex: TextureRect = null
var _vqa_image: Image = null
var _vqa_texture: ImageTexture = null
var _vqa_audio: AudioStreamPlayer = null
var _vqa_time := 0.0


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


	if Lang.code() != "en" and ContentPaths.mix_dir_de() == "":
		var loc := "%s/%s/%s.ogv" % [DIR, Lang.code(), name.get_basename()]
		if ResourceLoader.exists(loc):
			return _play_file(host, loc)


	var vqa := _open_vqa(name)
	if vqa != null:
		print("Video: ", name, ".vqa aus dem Archiv (", vqa.frame_count(), " Bilder)")
		var mv := Movie.new()
		mv.layer = 128
		host.get_tree().current_scene.add_child(mv)
		mv._start_vqa(vqa)
		return mv
	return _play_file(host, path(name))


static func _play_file(host: Node, vpath: String) -> Movie:
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


static func _open_vqa(name: String) -> VqaPlayer:
	var c := ContentPaths.archives()
	if c == null:
		return null
	var data := c.movie_bytes(name.get_basename())
	if data.is_empty():
		return null
	var v := VqaPlayer.new()
	if not v.open_buffer(data):
		print("Video: ", name, " nicht lesbar (", v.last_error(), ")")
		return null
	return v


func _start_vqa(v: VqaPlayer) -> void:
	_vqa = v
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
	_vqa_tex = TextureRect.new()
	_vqa_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_vqa_tex.stretch_mode = TextureRect.STRETCH_SCALE
	_vqa_tex.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	box.add_child(_vqa_tex)
	_vqa.next_frame()
	_vqa_image = _vqa.frame_image()
	_vqa_texture = ImageTexture.create_from_image(_vqa_image)
	_vqa_tex.texture = _vqa_texture
	var stream := _vqa.audio_stream()
	if stream != null:
		_vqa_audio = AudioStreamPlayer.new()
		_vqa_audio.bus = "Video"
		_vqa_audio.stream = stream
		add_child(_vqa_audio)
		_vqa_audio.play()
	MusicPlayer.set_paused(true)
	set_process(true)


func _process(delta: float) -> void:
	if _vqa == null or _done:
		return
	_vqa_time += delta
	var t := _vqa_audio.get_playback_position() if _vqa_audio != null else _vqa_time
	var want := int(t * _vqa.fps())
	if want <= _vqa.current_frame():
		return
	var steps := mini(want - _vqa.current_frame(), 4)
	for _i in steps:
		if not _vqa.next_frame():
			_finish()
			return
	if _vqa.blit_into(_vqa_image):
		_vqa_texture.update(_vqa_image)


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
	set_process(false)
	if _player != null:
		_player.stop()
	if _vqa_audio != null:
		_vqa_audio.stop()
	_vqa = null
	MusicPlayer.set_paused(false)
	finished.emit()
	queue_free()
