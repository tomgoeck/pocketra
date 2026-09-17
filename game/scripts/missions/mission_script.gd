

class_name MissionScript
extends RefCounted

var api: MissionApi
var difficulty := "normal"


func world_loaded() -> void:
	pass


func tick() -> void:
	pass


func test_force() -> void:
	pass


func init_objectives(owner: int) -> void:
	_owner = owner
	api.on_player_won(func():
		api.after_delay(api.seconds(1), func(): api.play_speech_notification(_owner, "MissionAccomplished")))
	api.on_player_lost(func():
		api.after_delay(api.seconds(1), func(): api.play_speech_notification(_owner, "MissionFailed")))


var _owner := 0


func random(list: Array):
	return list[randi() % list.size()]


func random_integer(lo: int, hi: int) -> int:
	if hi <= lo:
		return lo
	return randi_range(lo, hi - 1)
