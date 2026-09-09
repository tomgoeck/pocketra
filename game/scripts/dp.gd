

class_name Dp


const SHORT_REF_DP := 520.0


const DESKTOP_MIN_PX_PER_DP := 0.75
const DESKTOP_MAX_PX_PER_DP := 4.5

static var _scale := -1.0
static var _dpi := -1.0
static var _px_per_dp := -1.0


static var _dpi_forced := false


static var _ui_scale := 1.0


static func _forced_dpi() -> float:
	var args := OS.get_cmdline_user_args()
	var k := args.find("--dpi")
	return float(args[k + 1]) if (k >= 0 and k + 1 < args.size()) else 0.0


static func dpi() -> float:
	if _dpi < 0.0:
		_dpi = _forced_dpi()
		_dpi_forced = _dpi > 0.0
		if _dpi <= 0.0:
			_dpi = DisplayServer.screen_get_dpi()

		if _dpi < 160.0:
			_dpi = 160.0
	return _dpi


static func window_scaled() -> bool:
	return not _dpi_forced and OS.get_name() not in ["Android", "iOS", "Web"]


static func scale() -> float:
	if _scale < 0.0:
		var size := DisplayServer.window_get_size()
		if size.x <= 0 or size.y <= 0:
			size = DisplayServer.screen_get_size()
		var short_px := minf(size.x, size.y)
		var d := dpi()
		if window_scaled():


			var per_dp := clampf(short_px / SHORT_REF_DP, DESKTOP_MIN_PX_PER_DP, DESKTOP_MAX_PX_PER_DP)
			_scale = per_dp / (d / 160.0)
		else:
			_scale = clampf(short_px * 160.0 / d / SHORT_REF_DP, 0.6, 1.0)
	return _scale


static func invalidate() -> void:
	_scale = -1.0
	_dpi = -1.0
	_px_per_dp = -1.0


static func window_changed() -> void:
	_scale = -1.0
	_px_per_dp = -1.0


static func set_forced_dpi(v: float) -> void:
	_dpi = v if v > 0.0 else -1.0
	_dpi_forced = v > 0.0
	_scale = -1.0
	_px_per_dp = -1.0


static func ui_scale() -> float:
	return _ui_scale


static func set_ui_scale(f: float) -> void:
	_ui_scale = clampf(f, 0.8, 1.25)
	_px_per_dp = -1.0


static func safe_rect() -> Rect2:
	var size := DisplayServer.window_get_size()
	var full := Rect2(Vector2.ZERO, Vector2(size))
	var args := OS.get_cmdline_user_args()
	var k := args.find("--safe-area")
	if k >= 0 and k + 1 < args.size():
		var v: PackedStringArray = args[k + 1].split(",")
		if v.size() == 4:
			var top := float(v[0])
			var bottom := float(v[1])
			var left := float(v[2])
			var right := float(v[3])
			return Rect2(left, top, maxf(size.x - left - right, 1.0), maxf(size.y - top - bottom, 1.0))


	if OS.get_name() not in ["Android", "iOS"]:
		return full
	var safe := DisplayServer.get_display_safe_area()
	if safe.size.x <= 0 or safe.size.y <= 0:
		return full


	var r := Rect2(Vector2(safe.position), Vector2(safe.size))
	if r.size.x >= size.x and r.size.y >= size.y:
		return full
	return Rect2(Vector2.ZERO, Vector2(size)).intersection(Rect2(r.position, r.size))


static func px(dp: float) -> float:
	if _px_per_dp < 0.0:
		_px_per_dp = dpi() / 160.0 * scale() * _ui_scale
	return dp * _px_per_dp


static func px_per_dp() -> float:
	return px(1.0)


static func device_px(device_dp: float) -> float:
	return device_dp * dpi() / 160.0


static func to_device_dp(px_value: float) -> float:
	return px_value * 160.0 / dpi()
