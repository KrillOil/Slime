extends Node2D

const Serializer := preload("res://better_spewing/contracts/canonical_serializer.gd")
const Tuning := preload("res://better_spewing/contracts/goo_tuning.gd")
const Runner := preload("res://better_spewing/runner/authoritative_runner.gd")
const Config := preload("res://better_spewing/benchmarks/flow_benchmark_config.gd")

const WARMUP_SECONDS := 10.0
const MEASURE_SECONDS := 120.0
const TICK_SECONDS := 1.0 / 60.0
const HISTORY_INTERVAL_TICKS := 60

var stress_runner: RefCounted
var stress_room: Dictionary
var normal_runner: RefCounted
var variant := "canonical10"
var draw_stride := 1
var stress_core_us: Array[int] = []
var stress_runner_us: Array[int] = []
var stress_hash_us: Array[int] = []
var normal_core_us: Array[int] = []
var normal_runner_us: Array[int] = []
var frame_us: Array[int] = []
var object_history: Array = []
var elapsed := 0.0
var wall_start_us := 0
var previous_frame_us := 0
var accumulator := 0.0
var measured_frames := 0
var catchup_frames := 0
var dropped_ticks := 0
var replay_divergence := 0
var replay_probe_count := 0
var ledger_errors := 0
var category_errors := 0
var first_lane_report: Dictionary = {}
var lanes_reached := false
var measurement_start_tick := 0
var completed := false


func _ready() -> void:
	variant = _requested_variant()
	draw_stride = 4 if variant != "canonical10" else 1
	var stress := Config.build_stress_runner()
	stress_runner = stress.runner
	stress_room = stress.room
	var normal := Config.build_normal_runner()
	normal_runner = normal.runner
	wall_start_us = Time.get_ticks_usec()
	previous_frame_us = wall_start_us
	$ResultLabel.text = "Preparing Package 2C continuous benchmark: %s" % variant


func _process(_delta: float) -> void:
	if completed:
		return
	var now_us := Time.get_ticks_usec()
	var actual_frame_us := now_us - previous_frame_us
	previous_frame_us = now_us
	elapsed = float(now_us - wall_start_us) / 1_000_000.0
	accumulator += float(actual_frame_us) / 1_000_000.0
	var recording := elapsed > WARMUP_SECONDS
	if recording:
		frame_us.append(actual_frame_us)
		measured_frames += 1
	var ticks_due := floori(accumulator / TICK_SECONDS)
	if ticks_due > 0:
		accumulator -= TICK_SECONDS
		if recording and measurement_start_tick == 0:
			measurement_start_tick = stress_runner.state.tick
		_run_continuous_pair(recording)
	if ticks_due > 1:
		catchup_frames += 1
		dropped_ticks += ticks_due - 1
		accumulator = fmod(accumulator, TICK_SECONDS)
	$ResultLabel.text = "%s %s %.1f / %.0f seconds tick=%d" % [
		variant,
		"Measuring" if recording else "Warming up",
		maxf(elapsed - WARMUP_SECONDS, 0.0),
		MEASURE_SECONDS,
		stress_runner.state.tick,
	]
	queue_redraw()
	if elapsed >= WARMUP_SECONDS + MEASURE_SECONDS:
		_complete()


func _run_continuous_pair(record: bool) -> void:
	var frame := Config.no_action_frame(stress_runner.state)
	var probe_runner: RefCounted
	if record and stress_runner.state.tick % HISTORY_INTERVAL_TICKS == 0:
		probe_runner = Runner.new(stress_runner.state.duplicate(true), stress_room)
	var stress_start := Time.get_ticks_usec()
	var stress_result: Dictionary = stress_runner.step_frame(frame)
	var stress_duration := Time.get_ticks_usec() - stress_start

	var normal_start := Time.get_ticks_usec()
	var normal_result: Dictionary = normal_runner.step_frame(
		Config.no_action_frame(normal_runner.state)
	)
	var normal_duration := Time.get_ticks_usec() - normal_start
	if not stress_result.ok or not normal_result.ok:
		ledger_errors += 1
		return
	if first_lane_report.is_empty():
		first_lane_report = Config.stress_lane_report(stress_result, stress_runner.state)
		lanes_reached = Config.stress_lanes_reached(first_lane_report)
	var current_report := Config.stress_lane_report(stress_result, stress_runner.state)
	if current_report.ledger_error != 0:
		ledger_errors += 1
	if current_report.category_error != 0:
		category_errors += 1
	if probe_runner != null:
		var probe: Dictionary = probe_runner.step_frame(frame)
		replay_probe_count += 1
		if not probe.ok or probe.hash != stress_result.hash:
			replay_divergence += 1
	if record:
		stress_core_us.append(stress_runner.last_simulation_duration_us)
		stress_runner_us.append(stress_duration)
		stress_hash_us.append(stress_runner.last_hash_duration_us)
		normal_core_us.append(normal_runner.last_simulation_duration_us)
		normal_runner_us.append(normal_duration)
		if stress_runner.state.tick % HISTORY_INTERVAL_TICKS == 0:
			object_history.append(_history_record(current_report))


func _history_record(report: Dictionary) -> Dictionary:
	return {
		"authoritative_tick": stress_runner.state.tick,
		"packets": report.packet_count,
		"active": report.active_after,
		"drain_records": stress_runner.state.drain_queue.size(),
		"settled_nonzero": _nonzero(stress_runner.state.settled_cells),
		"state_hash": Serializer.state_hash(stress_runner.state),
	}


func _complete() -> void:
	completed = true
	var measured_seconds := maxf(elapsed - WARMUP_SECONDS, 0.001)
	if object_history.is_empty():
		object_history.append(_history_record(
			Config.stress_lane_report(
				{"simulation": {"flow": {"selected": [], "phase_b_pairs_scanned": 0}}},
				stress_runner.state
			)
		))
	var result := {
		"schema": "package-2c-flow-benchmark-result-v2",
		"continuous_authority": true,
		"variant": variant,
		"platform": "web" if OS.get_name() == "Web" else "desktop",
		"timestamp_utc": Time.get_datetime_string_from_system(true),
		"viewport": [960, 540],
		"export_mode": "release" if OS.get_name() == "Web" else "desktop-debug",
		"developer_tools_open": false,
		"warmup_seconds": WARMUP_SECONDS,
		"measured_seconds": measured_seconds,
		"sample_count": stress_core_us.size(),
		"stress_simulation_ms": _summary(stress_core_us),
		"stress_full_runner_ms": _summary(stress_runner_us),
		"stress_checkpoint_hash_ms": _summary(stress_hash_us),
		"normal_simulation_ms": _summary(normal_core_us),
		"normal_full_runner_ms": _summary(normal_runner_us),
		"whole_frame_ms": _summary(frame_us),
		"measured_fps": float(measured_frames) / measured_seconds,
		"measurement_start_tick": measurement_start_tick,
		"maximum_authoritative_tick": stress_runner.state.tick,
		"measured_authoritative_ticks": stress_runner.state.tick - measurement_start_tick,
		"gameplay_affecting_dropped_ticks": dropped_ticks,
		"catchup_frames": catchup_frames,
		"replay_probe_count": replay_probe_count,
		"replay_divergence_count": replay_divergence,
		"ledger_error_count": ledger_errors,
		"category_error_count": category_errors,
		"stress_lanes": first_lane_report,
		"stress_lanes_reached": lanes_reached,
		"object_history": object_history,
		"steady_counts": _steady_counts(),
		"tuning": Tuning.VALUES.duplicate(true),
		"tuning_hash": Tuning.canonical_hash(),
		"room_hash": stress_room.room_hash.hex_encode(),
		"occupancy_hash": stress_room.occupancy_hash.hex_encode(),
		"deferred": [
			"128 suction jobs",
			"four coverable hazard spans",
			"repeated player immersion transitions",
		],
		"raw": {
			"stress_simulation_us": stress_core_us,
			"stress_full_runner_us": stress_runner_us,
			"stress_checkpoint_hash_us": stress_hash_us,
			"normal_simulation_us": normal_core_us,
			"normal_full_runner_us": normal_runner_us,
			"whole_frame_us": frame_us,
		},
	}
	var encoded := JSON.stringify(result)
	$ResultLabel.text = "P2C_COMPLETE\n%s" % encoded
	print("P2C_BENCHMARK_RESULT %s" % encoded)
	if OS.get_name() == "Web":
		JavaScriptBridge.eval(
			(
				"window.P2C_RESULT=%s;"
				+ "document.title='P2C_COMPLETE';"
				+ "fetch('/p2c-result',{method:'POST',"
				+ "headers:{'Content-Type':'application/json'},"
				+ "body:JSON.stringify(window.P2C_RESULT)});"
			) % encoded
		)
	else:
		var file := FileAccess.open(
			"user://package_2c_%s_desktop_result.json" % variant,
			FileAccess.WRITE
		)
		if file != null:
			file.store_string(encoded)
		get_tree().quit()


func _requested_variant() -> String:
	if OS.get_name() == "Web":
		var query = JavaScriptBridge.eval(
			"new URLSearchParams(location.search).get('variant')||'canonical10'"
		)
		return str(query)
	var requested := OS.get_environment("P2C_VARIANT")
	return requested if not requested.is_empty() else "canonical10"


func _summary(samples: Array[int]) -> Dictionary:
	if samples.is_empty():
		return {"p95": 0.0, "p99": 0.0, "max": 0.0, "mean": 0.0}
	var ordered := samples.duplicate()
	ordered.sort()
	var total := 0
	for sample in ordered:
		total += sample
	return {
		"p95": float(ordered[ceili(ordered.size() * 0.95) - 1]) / 1000.0,
		"p99": float(ordered[ceili(ordered.size() * 0.99) - 1]) / 1000.0,
		"max": float(ordered[-1]) / 1000.0,
		"mean": float(total) / float(ordered.size()) / 1000.0,
	}


func _steady_counts() -> Dictionary:
	if object_history.is_empty():
		return {"steady": false}
	var first: Dictionary = object_history[0]
	var steady := true
	for sample in object_history:
		steady = steady \
			and sample.packets == first.packets \
			and sample.active == first.active \
			and sample.drain_records == first.drain_records \
			and sample.settled_nonzero == first.settled_nonzero
	return {
		"steady": steady,
		"packets": first.packets,
		"active": first.active,
		"drain_records": first.drain_records,
		"settled_nonzero": first.settled_nonzero,
	}


func _nonzero(values: Array) -> int:
	var result := 0
	for value in values:
		if value > 0:
			result += 1
	return result


func _draw() -> void:
	if stress_runner == null:
		return
	var width: int = Tuning.VALUES.grid_width_cells
	var cell_size: int = Tuning.VALUES.grid_cell_size_px
	for cell_id in range(0, stress_runner.state.settled_cells.size(), draw_stride):
		var volume: int = stress_runner.state.settled_cells[cell_id]
		if volume <= 0:
			continue
		var x: int = cell_id % width
		var y: int = cell_id / width
		draw_rect(
			Rect2(x * cell_size, y * cell_size, cell_size, cell_size),
			Color(0.16, 0.78, 0.28, 0.45),
			true
		)
	for packet in stress_runner.state.packets:
		draw_circle(
			Vector2(packet.position_x_fp, packet.position_y_fp) / 256.0,
			2.0,
			Color(0.72, 1.0, 0.35, 0.9)
		)
