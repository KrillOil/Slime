extends SceneTree

const GooGridScript := preload("res://scripts/goo_grid.gd")


func _init() -> void:
	var grid := GooGridScript.new()
	root.add_child(grid)
	var start_total: float = grid.total_stored_goo()
	var deposited: float = grid.spew(Vector2(200, 200), Vector2.RIGHT, 12.0)
	var after_spew: float = grid.total_stored_goo()
	var recovered: float = grid.gulp(Vector2(245, 200), 12.0)
	var after_gulp: float = grid.total_stored_goo()
	var ok: bool = (
		is_equal_approx(start_total, 0.0)
		and deposited > 0.0
		and is_equal_approx(after_spew, deposited)
		and recovered > 0.0
		and is_equal_approx(after_spew - after_gulp, recovered)
	)
	print("GOO_VALIDATION deposited=%.3f recovered=%.3f stored=%.3f result=%s" % [
		deposited, recovered, after_gulp, "PASS" if ok else "FAIL"
	])
	quit(0 if ok else 1)
