extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var first_room := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(first_room)
	current_scene = first_room
	await process_frame
	var all_ok := true
	for expected_room in range(2, 5):
		var previous_room: int = current_scene.room_index
		current_scene._on_goal_body_entered(current_scene.player)
		await create_timer(0.55).timeout
		await process_frame
		var transitioned: bool = current_scene != null and current_scene.room_index == expected_room
		print("PROGRESSION_VALIDATION from=%d to=%d result=%s" % [
			previous_room, expected_room, "PASS" if transitioned else "FAIL"
		])
		all_ok = all_ok and transitioned
		if not transitioned:
			break
	if all_ok:
		current_scene._on_goal_body_entered(current_scene.player)
		await process_frame
		var won: bool = current_scene.message_label.visible and "YOU WIN!" in current_scene.message_label.text
		var stopped: bool = not current_scene.player.controls_enabled
		print("WIN_VALIDATION visible=%s controls_stopped=%s result=%s" % [
			won, stopped, "PASS" if won and stopped else "FAIL"
		])
		all_ok = all_ok and won and stopped
	print("PROGRESSION_SUITE result=%s" % ["PASS" if all_ok else "FAIL"])
	quit(0 if all_ok else 1)
