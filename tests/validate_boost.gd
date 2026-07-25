extends SceneTree

const PlayerScript := preload("res://scripts/player.gd")


func _init() -> void:
	var player := PlayerScript.new()
	var normal_speed: float = player.take_jump_speed()
	player.recent_down_spew_time = 0.4
	player.down_spew_charge = player.BOOST_CHARGE_REQUIRED
	var boost_speed: float = player.take_jump_speed()
	var consumed: bool = is_zero_approx(player.recent_down_spew_time) and is_zero_approx(player.down_spew_charge)
	var ok: bool = normal_speed == player.JUMP_SPEED and boost_speed == player.BOOST_JUMP_SPEED and consumed
	print("BOOST_VALIDATION normal=%.1f boost=%.1f consumed=%s result=%s" % [
		normal_speed, boost_speed, consumed, "PASS" if ok else "FAIL"
	])
	player.free()
	quit(0 if ok else 1)
