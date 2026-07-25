extends Node2D

const Serializer := preload("res://better_spewing/contracts/canonical_serializer.gd")
const Config := preload("res://better_spewing/benchmarks/flow_benchmark_config.gd")

const WARMUP_SECONDS := 10.0
const MEASURE_SECONDS := 120.0
const TICK_SECONDS := 1.0 / 60.0

var stress_runner: RefCounted
var stress_template: Dictionary
var normal_runner: RefCounted
var stress_us: Array[int] = []
var normal_us: Array[int] = []
var frame_us: Array[int] = []
var object_history: Array = []
var elapsed := 0.0
var wall_start_us := 0
var previous_frame_us := 0
var accumulator := 0.0
var measured_frames := 0
var total_ticks := 0
var catchup_frames := 0
var dropped_ticks := 0
var replay_divergence := 0
var ledger_errors := 0
var category_errors := 0
var expected_stress_hash := ""
var lane_report: Dictionary = {}
var completed := false
var status_text := "Preparing Package 2C benchmark"


func _ready() -> void:
	var stress := Config.build_stress_runner()
	stress_runner = stress.runner
	stress_template = stress.template
	var normal := Config.build_normal_runner()
	normal_runner = normal.runner
	wall_start_us = Time.get_ticks_usec()
	previous_frame_us = wall_start_us
	$ResultLabel.text = status_text


func _process(_delta: float) -> void:
	if completed:
		return
	var now_us := Time.get_ticks_usec()
	var actual_frame_us := now_us - previous_frame_us
	previous_frame_us = now_us
	elapsed = float(now_us - wall_start_us) / 1_000_000.0
	accumulator += float(actual_frame_us) / 1_000_000.0
	if elapsed > WARMUP_SECONDS:
		frame_us.append(actual_frame_us)
		measured_frames += 1
	var ticks_due := floori(accumulator / TICK_SECONDS)
	if ticks_due > 0:
		accumulator -= TICK_SECONDS
		_run_authoritative_pair(elapsed > WARMUP_SECONDS)
	if ticks_due > 1:
		catchup_frames += 1
		dropped_ticks += ticks_due - 1
		accumulator = fmod(accumulator, TICK_SECONDS)
	status_text = "%s %.1f / %.0f seconds" % [
		"Measuring" if elapsed > WARMUP_SECONDS else "Warming up",
		maxf(elapsed - WARMUP_SECONDS, 0.0),
		MEASURE_SECONDS,
	]
	$ResultLabel.text = status_text
	queue_redraw()
	if elapsed >= WARMUP_SECONDS + MEASURE_SECONDS:
		_complete()


func _run_authoritative_pair(record: bool) -> void:
	stress_runner.state = stress_template.duplicate(true)
	stress_runner.checkpoint_hashes.clear()
	var stress_start := Time.get_ticks_usec()
	var stress_result: Dictionary = stress_runner.step_frame(
		Config.no_action_frame(stress_runner.state)
	)
	var stress_duration := Time.get_ticks_usec() - stress_start

	var normal_start := Time.get_ticks_usec()
	var normal_result: Dictionary = normal_runner.step_frame(
		Config.no_action_frame(normal_runner.state)
	)
	var normal_duration := Time.get_ticks_usec() - normal_start
	if not stress_result.ok or not normal_result.ok:
		ledger_errors += 1
		return
	lane_report = Config.stress_lane_report(stress_result, stress_runner.state)
	if expected_stress_hash.is_empty():
		expected_stress_hash = stress_result.hash
	elif stress_result.hash != expected_stress_hash:
		replay_divergence += 1
	if lane_report.ledger_error != 0:
		ledger_errors += 1
	if lane_report.category_error != 0:
		category_errors += 1
	if record:
		stress_us.append(stress_duration)
		normal_us.append(normal_duration)
		total_ticks += 1
		if total_ticks % 60 == 0:
			object_history.append({
				"sample_tick": total_ticks,
				"packets": lane_report.packet_count,
				"active": lane_report.active_after,
				"drain_records": stress_runner.state.drain_queue.size(),
				"settled_nonzero": _nonzero(stress_runner.state.settled_cells),
			})


func _complete() -> void:
	completed = true
	var measured_seconds := maxf(elapsed - WARMUP_SECONDS, 0.001)
	var result := {
		"schema": "package-2c-flow-benchmark-result-v1",
		"platform": "web" if OS.get_name() == "Web" else "desktop",
		"timestamp_utc": Time.get_datetime_string_from_system(true),
		"viewport": [960, 540],
		"export_mode": "release" if OS.get_name() == "Web" else "desktop-debug",
		"developer_tools_open": false,
		"warmup_seconds": WARMUP_SECONDS,
		"measured_seconds": measured_seconds,
		"sample_count": stress_us.size(),
		"stress_simulation_ms": _summary(stress_us),
		"normal_simulation_ms": _summary(normal_us),
		"whole_frame_ms": _summary(frame_us),
		"measured_fps": float(measured_frames) / measured_seconds,
		"maximum_authoritative_tick": total_ticks,
		"gameplay_affecting_dropped_ticks": dropped_ticks,
		"catchup_frames": catchup_frames,
		"replay_divergence_count": replay_divergence,
		"ledger_error_count": ledger_errors,
		"category_error_count": category_errors,
		"stress_lanes": lane_report,
		"stress_lanes_reached": Config.stress_lanes_reached(lane_report),
		"object_history": object_history,
		"steady_counts": _steady_counts(),
		"deferred": [
			"128 suction jobs",
			"four coverable hazard spans",
			"repeated player immersion transitions",
		],
		"fallback_decision": "pending threshold evaluation",
		"raw": {
			"stress_tick_us": stress_us,
			"normal_tick_us": normal_us,
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
		var file := FileAccess.open("user://package_2c_desktop_result.json", FileAccess.WRITE)
		if file != null:
			file.store_string(encoded)
		get_tree().quit()


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
	for cell_id in stress_runner.state.settled_cells.size():
		var volume: int = stress_runner.state.settled_cells[cell_id]
		if volume <= 0:
			continue
		var x: int = cell_id % 96
		var y: int = cell_id / 96
		var alpha := 0.18 + 0.55 * float(volume) / 16.0
		draw_rect(Rect2(x * 10, y * 10, 10, 10), Color(0.18, 0.82, 0.36, alpha))
	for packet in stress_runner.state.packets:
		draw_circle(
			Vector2(packet.position_x_fp, packet.position_y_fp) / 256.0,
			2.0,
			Color(0.65, 1.0, 0.72, 0.35)
		)
