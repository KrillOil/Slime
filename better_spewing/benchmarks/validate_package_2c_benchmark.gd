extends SceneTree

const Serializer := preload("res://better_spewing/contracts/canonical_serializer.gd")
const Config := preload("res://better_spewing/benchmarks/flow_benchmark_config.gd")

var passed := 0
var failed := 0


func _init() -> void:
	var built := Config.build_stress_runner()
	var runner: RefCounted = built.runner
	var before_hash := Serializer.state_hash(runner.state)
	var result: Dictionary = runner.step_frame(Config.no_action_frame(runner.state))
	_check(result.ok, "stress runner performs a real authoritative tick")
	var report := Config.stress_lane_report(result, runner.state)
	_check(Config.stress_lanes_reached(report), "all implemented stress lanes reach their declared limits")
	_check(report.selected_cells == 1536 and report.lateral_pairs == 2048, "active and lateral work budgets saturate exactly")
	_check(report.packet_count == 192 and report.airborne_q == 192, "192 conserved AIRBORNE packets remain under blocked deposition")
	_check(report.drain_q == 16 and report.reserve_q == 1600, "ready drain remains queued while reserve is full")
	_check(report.sleeping_cells >= 100 and report.active_after > 0, "sleeping and active pool regions coexist")
	_check(report.ledger_error == 0 and report.category_error == 0 and report.canonical, "stress tick has zero ledger/category error and canonical state")
	var repeated := Config.build_stress_runner()
	var repeated_result: Dictionary = repeated.runner.step_frame(
		Config.no_action_frame(repeated.runner.state)
	)
	_check(
		repeated_result.ok
		and result.hash == repeated_result.hash
		and before_hash == Serializer.state_hash(repeated.template),
		"fresh stress configurations produce identical before/after hashes"
	)
	var normal := Config.build_normal_runner()
	var normal_result: Dictionary = normal.runner.step_frame(
		Config.no_action_frame(normal.runner.state)
	)
	_check(normal_result.ok and not normal_result.hash.is_empty(), "normal isolated workload uses the authoritative runner")
	var desktop := _read_json("res://better_spewing/benchmarks/results/desktop_raw.json")
	var web := _read_json("res://better_spewing/benchmarks/results/web_chrome_raw.json")
	var evidence := _read_json("res://better_spewing/benchmarks/results/package_2c_evidence.json")
	_check(
		not desktop.is_empty() and not web.is_empty() and not evidence.is_empty(),
		"checked-in desktop, installed-Chrome web, and summary evidence parse"
	)
	_check(
		desktop.platform == "desktop"
		and web.platform == "web"
		and desktop.measured_seconds >= 120.0
		and web.measured_seconds >= 120.0,
		"both platforms retain the required measured duration"
	)
	_check(
		desktop.raw.stress_tick_us.size() == desktop.sample_count
		and web.raw.stress_tick_us.size() == web.sample_count,
		"raw stress samples match the declared sample counts"
	)
	_check(
		desktop.stress_lanes_reached and web.stress_lanes_reached
		and desktop.steady_counts.steady and web.steady_counts.steady,
		"both measured runs saturate lanes and retain steady authority counts"
	)
	_check(
		desktop.replay_divergence_count == 0
		and web.replay_divergence_count == 0
		and desktop.ledger_error_count == 0
		and web.ledger_error_count == 0
		and desktop.category_error_count == 0
		and web.category_error_count == 0,
		"both measured runs retain replay, ledger, and category integrity"
	)
	_check(
		not evidence.authoritative
		and evidence.excluded_from_state_replay_and_hashes
		and not evidence.fallback_decision.thresholds_passed
		and not evidence.fallback_decision.authoritative_tuning_changed,
		"timing evidence remains non-authoritative with its fallback disposition recorded"
	)
	print("P2C_LANES %s" % JSON.stringify(report))
	print("P2C_BENCHMARK_SUITE passed=%d failed=%d result=%s" % [
		passed, failed, "PASS" if failed == 0 else "FAIL"
	])
	quit(0 if failed == 0 else 1)


func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		printerr("P2C_BENCHMARK_CHECK_FAIL: %s" % label)


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var value = JSON.parse_string(file.get_as_text())
	return value if value is Dictionary else {}
