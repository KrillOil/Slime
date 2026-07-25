extends SceneTree

const GooGridScript := preload("res://scripts/goo_grid.gd")
const PlayerScript := preload("res://scripts/player.gd")


func _init() -> void:
	var grid := GooGridScript.new()
	root.add_child(grid)
	var player := PlayerScript.new()
	root.add_child(player)
	player.global_position = Vector2(200, 200)
	player.goo_grid = grid
	var before: float = grid.sample_wetness(player.global_position, 38.0)
	grid.spew(player.global_position, Vector2.DOWN, 25.0)
	var after: float = grid.sample_wetness(player.global_position, 38.0)
	player._update_swimming_state()
	var ok: bool = before < player.SWIM_WETNESS_THRESHOLD and after >= player.SWIM_WETNESS_THRESHOLD and player.is_swimming
	print("SWIM_VALIDATION before=%.3f after=%.3f swimming=%s result=%s" % [
		before, after, player.is_swimming, "PASS" if ok else "FAIL"
	])
	quit(0 if ok else 1)
