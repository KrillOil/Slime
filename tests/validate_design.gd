extends SceneTree

const PlayerScript := preload("res://scripts/player.gd")


func _init() -> void:
	var normal_jump_height: float = PlayerScript.JUMP_SPEED * PlayerScript.JUMP_SPEED / (2.0 * PlayerScript.GRAVITY)
	var boost_jump_height: float = PlayerScript.BOOST_JUMP_SPEED * PlayerScript.BOOST_JUMP_SPEED / (2.0 * PlayerScript.GRAVITY)
	var room3_rise := 180.0
	var room4_rise := 170.0
	var room4_pit_width := 460.0
	var room4_swim_cost: float = room4_pit_width / PlayerScript.SWIM_SPEED * PlayerScript.SPEW_RATE
	var room4_remaining := 68.0 - room4_swim_cost
	var boost_required: float = PlayerScript.BOOST_CHARGE_REQUIRED
	var heights_ok := normal_jump_height < room3_rise and boost_jump_height > room3_rise and boost_jump_height > room4_rise
	var gulp_required := room4_remaining < boost_required
	var room4_crossable := room4_swim_cost < 68.0
	var ok := heights_ok and gulp_required and room4_crossable
	print("DESIGN_VALIDATION normal_height=%.1f boost_height=%.1f room4_swim_cost=%.1f remaining=%.1f gulp_required=%s result=%s" % [
		normal_jump_height, boost_jump_height, room4_swim_cost, room4_remaining, gulp_required, "PASS" if ok else "FAIL"
	])
	quit(0 if ok else 1)
