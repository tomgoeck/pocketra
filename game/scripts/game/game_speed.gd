

class_name GameSpeed
extends RefCounted

const SETTINGS := "user://settings.cfg"


const TIMESTEPS := [80, 50, 40, 30, 20, 10]
const KEYS := ["speed.slowest", "speed.slower", "speed.normal", "speed.fast", "speed.faster",
		"speed.superfast"]
const DEFAULT_INDEX := 2


const CATCHUP_SECONDS := 0.16

const MIN_CATCHUP := 8

static var _index := -1


static func index() -> int:
	if _index < 0:
		var args := OS.get_cmdline_user_args()
		var k := args.find("--game-speed")
		if k >= 0 and k + 1 < args.size():
			_index = clampi(int(args[k + 1]), 0, TIMESTEPS.size() - 1)
			return _index
		var cfg := ConfigFile.new()
		_index = DEFAULT_INDEX
		if cfg.load(SETTINGS) == OK:
			_index = clampi(int(cfg.get_value("general", "game_speed", DEFAULT_INDEX)), 0, TIMESTEPS.size() - 1)
	return _index


static func set_index(i: int) -> void:
	_index = clampi(i, 0, TIMESTEPS.size() - 1)
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value("general", "game_speed", _index)
	cfg.save(SETTINGS)


static func tick_seconds() -> float:
	return TIMESTEPS[index()] / 1000.0


static func max_catchup() -> int:
	return maxi(MIN_CATCHUP, ceili(CATCHUP_SECONDS / maxf(tick_seconds(), 0.001)))


static func name_key() -> String:
	return KEYS[index()]


static func names() -> Array:
	var out: Array = []
	for k in KEYS:
		out.append(TranslationServer.translate(k))
	return out
