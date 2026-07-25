extends RefCounted

const Contracts := preload("res://better_spewing/contracts/goo_contracts.gd")
const AimQuantizer := preload("res://better_spewing/aim/aim_quantizer.gd")
const MouthDerivation := preload("res://better_spewing/runner/mouth_derivation.gd")

var entries: Array[Vector2i]
var has_last_valid_aim := false
var last_valid_aim := 0


func _init(direction_entries: Array[Vector2i]) -> void:
	entries = direction_entries


func sample_snapshot(tick: int, snapshot: Dictionary, player_state: Dictionary) -> Dictionary:
	var mouth := MouthDerivation.derive(player_state)
	var aim := AimQuantizer.resolve(
		int(snapshot.cursor_x_fp),
		int(snapshot.cursor_y_fp),
		mouth,
		has_last_valid_aim,
		last_valid_aim,
		int(player_state.facing),
		entries
	)
	var distance_x := int(snapshot.cursor_x_fp) - mouth.x
	var distance_y := int(snapshot.cursor_y_fp) - mouth.y
	if distance_x * distance_x + distance_y * distance_y >= AimQuantizer.MIN_CURSOR_DISTANCE_FP * AimQuantizer.MIN_CURSOR_DISTANCE_FP:
		has_last_valid_aim = true
		last_valid_aim = aim
	var action := Contracts.GooAction.NONE
	if bool(snapshot.spew_pressed):
		action = Contracts.GooAction.SPEW
	elif bool(snapshot.gulp_pressed):
		action = Contracts.GooAction.GULP
	return {
		"tick": tick,
		"move_x": clampi(int(snapshot.move_x), -1, 1),
		"move_y": clampi(int(snapshot.move_y), -1, 1),
		"jump_pressed": bool(snapshot.jump_pressed),
		"goo_action": action,
		"aim_angle": aim,
		"asserted_mouth_x_fp": mouth.x,
		"asserted_mouth_y_fp": mouth.y,
	}
