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
	var desktop := _read_json("res://better_spewing/benchmarks/results/canonical10_continuous_desktop.json")
	var web := _read_json("res://better_spewing/benchmarks/results/canonical10_continuous_web_chrome.json")
	var cell15_desktop := _read_json("res://better_spewing/benchmarks/results/cell15_continuous_desktop.json")
	var cell15_web := _read_json("res://better_spewing/benchmarks/results/cell15_continuous_web_chrome.json")
	var ladder := _read_json("res://better_spewing/benchmarks/results/fallback_ladder.json")
	var evidence := _read_json("res://better_spewing/benchmarks/results/package_2c_evidence_v2.json")
	_check(
		not desktop.is_empty() and not web.is_empty()
		and not cell15_desktop.is_empty() and not cell15_web.is_empty()
		and not ladder.is_empty() and not evidence.is_empty(),
		"corrected continuous, fallback-ladder, and summary evidence parse"
	)
	_check(
		desktop.platform == "desktop"
		and web.platform == "web"
		and cell15_desktop.platform == "desktop"
		and cell15_web.platform == "web"
		and desktop.measured_seconds >= 120.0
		and web.measured_seconds >= 120.0
		and cell15_desktop.measured_seconds >= 120.0
		and cell15_web.measured_seconds >= 120.0,
		"canonical and terminal fallback retain 120-second desktop/Web durations"
	)
	_check(
		desktop.continuous_authority and web.continuous_authority
		and desktop.maximum_authoritative_tick > desktop.measurement_start_tick
		and web.maximum_authoritative_tick > web.measurement_start_tick
		and desktop.object_history.size() >= 3 and web.object_history.size() >= 3,
		"canonical measurements continuously evolve real authoritative ticks"
	)
	_check(
		desktop.raw.stress_simulation_us.size() == desktop.sample_count
		and desktop.raw.stress_full_runner_us.size() == desktop.sample_count
		and desktop.raw.stress_checkpoint_hash_us.size() == desktop.sample_count
		and web.raw.stress_simulation_us.size() == web.sample_count
		and web.raw.stress_full_runner_us.size() == web.sample_count
		and web.raw.stress_checkpoint_hash_us.size() == web.sample_count,
		"core simulation, full runner, and hash samples have separate complete scopes"
	)
	_check(
		desktop.replay_divergence_count == 0
		and web.replay_divergence_count == 0
		and desktop.replay_probe_count > 0 and web.replay_probe_count > 0
		and desktop.ledger_error_count == 0
		and web.ledger_error_count == 0
		and desktop.category_error_count == 0
		and web.category_error_count == 0,
		"continuous checkpoint-resume probes and conservation remain exact"
	)
	_check(
		desktop.stress_lanes_reached and web.stress_lanes_reached,
		"canonical continuous runs reach every declared stress lane"
	)
	_check(
		ladder.records.size() == 7
		and ladder.records[0].variant == "canonical10"
		and ladder.records[-1].variant == "cell15"
		and ladder.records[5].grid_cells == 3600
		and ladder.records[6].grid_cells == 2304
		and ladder.records.all(func(record): return record.resume_hash_identical and record.replay_round_trip),
		"ordered fallbacks rebuild 12/15px grids and retain replay/resume determinism"
	)
	_check(
		not cell15_desktop.stress_lanes_reached
		and not cell15_web.stress_lanes_reached
		and cell15_web.stress_lanes.lateral_pairs == 822
		and cell15_web.stress_simulation_ms.p95 > 4.0,
		"measured 15px terminal fallback fails timing and minimum lateral workload"
	)
	_check(
		not evidence.authoritative
		and evidence.excluded_from_state_replay_and_hashes
		and not evidence.fallback_decision.thresholds_passed
		and not evidence.fallback_decision.authoritative_tuning_accepted,
		"non-authoritative evidence records rejection of every measured fallback"
	)
	var proposal := FileAccess.get_file_as_string(
		"res://better_spewing/benchmarks/reduced_basin_column_proposal.md"
	)
	_check(
		proposal.contains("Proposed authority and schema")
		and proposal.contains("Player, immersion, hazard, and suction interfaces")
		and proposal.contains("Performance hypothesis and budgets")
		and proposal.contains("Creator decision requested")
		and proposal.contains("Rollback"),
		"reduced basin-column proposal covers every required decision surface"
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
