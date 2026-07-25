extends SceneTree

const LEVELS := [
	"res://scenes/game.tscn",
	"res://scenes/level_2.tscn",
	"res://scenes/level_3.tscn",
	"res://scenes/level_4.tscn",
]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var all_ok := true
	for index in LEVELS.size():
		var packed := load(LEVELS[index]) as PackedScene
		if packed == null:
			print("ROOM_VALIDATION room=%d result=FAIL_LOAD" % [index + 1])
			all_ok = false
			continue
		var room := packed.instantiate()
		root.add_child(room)
		var geometry_count: int = room.get_node("Geometry").get_child_count()
		var trigger_count: int = room.get_node("Triggers").get_child_count()
		var correct_index: bool = room.room_index == index + 1
		var room_ok := geometry_count >= 2 and trigger_count >= 1 and correct_index
		print("ROOM_VALIDATION room=%d solids=%d triggers=%d result=%s" % [
			index + 1, geometry_count, trigger_count, "PASS" if room_ok else "FAIL"
		])
		all_ok = all_ok and room_ok
		room.queue_free()
		await process_frame
	print("ROOM_SUITE result=%s" % ["PASS" if all_ok else "FAIL"])
	quit(0 if all_ok else 1)
