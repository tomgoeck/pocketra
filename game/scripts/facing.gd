

class_name Facing

const FULL := 1024

const CLASSIC_RANGES: Array[int] = [
	20, 56, 88, 132, 156, 184, 212, 240,
	268, 296, 324, 352, 384, 416, 452, 488,
	532, 568, 604, 644, 668, 696, 724, 752,
	780, 808, 836, 864, 896, 928, 964, 1000,
]


static func from_direction(dir: Vector2) -> int:

	var a := atan2(-dir.x, -dir.y) / TAU * FULL
	return posmod(int(round(a)), FULL)


static func to_frame(angle: int, facings: int, classic: bool) -> int:
	angle = posmod(angle, FULL)
	if classic:
		for i in CLASSIC_RANGES.size():
			if angle < CLASSIC_RANGES[i]:
				return i
		return 0
	var step := FULL / facings
	return ((angle + step / 2) / step) % facings


static func turn_towards(from: int, to: int, max_step: int) -> int:
	var diff := posmod(to - from + FULL / 2, FULL) - FULL / 2
	diff = clampi(diff, -max_step, max_step)
	return posmod(from + diff, FULL)
