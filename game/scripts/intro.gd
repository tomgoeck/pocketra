

extends Control


const BUNDLED_RATIO := 836.0 / 480.0
const MENU := "res://scenes/main_menu.tscn"

var _player: VideoStreamPlayer
var _done := false
var _queue: Array[String] = []


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var ratio := BUNDLED_RATIO
	if OriginalContent.video("prolog") != "":
		_queue.assign([OriginalContent.video("prolog"), OriginalContent.video("redintro")])
		ratio = 4.0 / 3.0
	else:
		_queue.assign(["res://assets/video/intro.ogv"])
	var k := args.find("--intro")
	if k >= 0 and k + 1 < args.size():
		_queue = [args[k + 1]]
	if args.has("--autostart") or args.has("--menu-screenshot") or args.has("--no-intro"):
		_finish()
		return
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var box := AspectRatioContainer.new()
	box.ratio = ratio
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(box)
	_player = VideoStreamPlayer.new()
	_player.bus = "Video"
	_player.expand = true
	_player.autoplay = false
	_player.finished.connect(_play_next)
	box.add_child(_player)
	MusicPlayer.set_paused(true)
	_play_next()


func _play_next() -> void:
	while not _queue.is_empty():
		var path: String = _queue.pop_front()
		var stream: VideoStream = Movie.load_stream(path) if path != "" else null
		if stream == null:
			print("Intro: kein Video unter ", path)
			continue
		_player.stream = stream
		_player.play()
		print("Intro: spielt ", path)
		return
	_finish()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_finish()


func _input(e: InputEvent) -> void:
	if (e is InputEventScreenTouch and e.pressed) or (e is InputEventMouseButton and e.pressed) \
			or (e is InputEventKey and e.pressed):
		_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	if _player != null:
		_player.stop()
	MusicPlayer.set_paused(false)
	get_tree().change_scene_to_file.call_deferred(MENU)
