extends RefCounted

const MouthDerivation := preload("res://better_spewing/runner/mouth_derivation.gd")

var frames: Array
var cursor := 0


func _init(ordered_frames: Array) -> void:
	frames = ordered_frames.duplicate(true)


func next_frame(expected_tick: int, state: Dictionary) -> Dictionary:
	if cursor >= frames.size():
		return {"ok": false, "error": "replay command stream exhausted", "frame": {}}
	var frame: Dictionary = frames[cursor]
	if frame.tick != expected_tick:
		return {"ok": false, "error": "replay tick mismatch", "frame": {}}
	var derived := MouthDerivation.derive(state.player)
	if frame.asserted_mouth_x_fp != derived.x:
		return {"ok": false, "error": "replay asserted mouth x mismatch", "frame": {}}
	if frame.asserted_mouth_y_fp != derived.y:
		return {"ok": false, "error": "replay asserted mouth y mismatch", "frame": {}}
	cursor += 1
	return {"ok": true, "error": "", "frame": frame.duplicate(true)}
