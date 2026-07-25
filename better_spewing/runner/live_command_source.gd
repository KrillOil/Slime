extends RefCounted

const CommandSampler := preload("res://better_spewing/runner/command_sampler.gd")

var sampler: RefCounted
var snapshots: Array[Dictionary] = []
var cursor := 0


func _init(direction_entries: Array[Vector2i]) -> void:
	sampler = CommandSampler.new(direction_entries)


static func capture_input_snapshot(cursor_global_fp: Vector2i) -> Dictionary:
	# This is the only Input-reading boundary. The returned plain-data snapshot
	# must be captured before the authoritative runner requests its tick frame.
	return {
		"move_x": roundi(Input.get_axis("move_left", "move_right")),
		"move_y": roundi(Input.get_axis("move_up", "move_down")),
		"jump_pressed": Input.is_action_just_pressed("jump"),
		"spew_pressed": Input.is_action_pressed("spew"),
		"gulp_pressed": Input.is_action_pressed("gulp"),
		"cursor_x_fp": cursor_global_fp.x,
		"cursor_y_fp": cursor_global_fp.y,
	}


func enqueue_snapshot(snapshot: Dictionary) -> void:
	snapshots.append(snapshot.duplicate(true))


func next_frame(expected_tick: int, state: Dictionary) -> Dictionary:
	if cursor >= snapshots.size():
		return {"ok": false, "error": "live snapshot queue exhausted"}
	var snapshot := snapshots[cursor]
	cursor += 1
	var frame: Dictionary = sampler.sample_snapshot(expected_tick, snapshot, state)
	return {"ok": true, "error": "", "frame": frame}
