extends SceneTree

const Tuning := preload("res://better_spewing/contracts/goo_tuning.gd")
const Serializer := preload("res://better_spewing/contracts/canonical_serializer.gd")
const ReplayCodec := preload("res://better_spewing/replay/replay_codec.gd")
const Runner := preload("res://better_spewing/runner/authoritative_runner.gd")
const Config := preload("res://better_spewing/benchmarks/flow_benchmark_config.gd")

const CONTINUOUS_TICKS := 3
const RESET_SAMPLES := 2


func _init() -> void:
	var variant := OS.get_environment("P2C_VARIANT")
	if variant.is_empty():
		variant = "canonical10"
	var tuning_error := Tuning.validate()
	if not tuning_error.is_empty():
		_fail("tuning invalid: %s" % tuning_error)
		return
	var built := Config.build_stress_runner()
	var runner: RefCounted = built.runner
	var room: Dictionary = built.room
	var initial_state_hash := Serializer.state_hash(runner.state)
	var frames: Array = []
	for tick in CONTINUOUS_TICKS:
		var frame := Config.no_action_frame(runner.state)
		frame.tick = tick
		frames.append(frame)
	var replay := ReplayCodec.encode(_header(room, runner.state), frames)
	if not replay.ok:
		_fail("replay encode failed: %s" % replay.error)
		return
	var decoded := ReplayCodec.decode(replay.bytes, {
		"room_definition_hash": room.room_hash,
		"tuning_hash": room.tuning_hash,
	})
	if not decoded.ok or decoded.frames != frames:
		_fail("replay rebuild/round-trip failed")
		return

	var core_us: Array[int] = []
	var runner_us: Array[int] = []
	var hash_us: Array[int] = []
	var first_report: Dictionary = {}
	var resume_identical := false
	for tick in CONTINUOUS_TICKS:
		var frame := Config.no_action_frame(runner.state)
		var probe: RefCounted
		if tick == 1:
			probe = Runner.new(runner.state.duplicate(true), room)
		var started := Time.get_ticks_usec()
		var result: Dictionary = runner.step_frame(frame)
		runner_us.append(Time.get_ticks_usec() - started)
		if not result.ok:
			_fail("continuous tick failed: %s" % result.error)
			return
		core_us.append(runner.last_simulation_duration_us)
		hash_us.append(runner.last_hash_duration_us)
		if tick == 0:
			first_report = Config.stress_lane_report(result, runner.state)
		if probe != null:
			var probe_result: Dictionary = probe.step_frame(frame)
			resume_identical = probe_result.ok and probe_result.hash == result.hash

	var reset_runner_us: Array[int] = []
	var reset_hashes: Array[String] = []
	for unused in RESET_SAMPLES:
		var reset := Config.build_stress_runner()
		var reset_runner: RefCounted = reset.runner
		var started := Time.get_ticks_usec()
		var reset_result: Dictionary = reset_runner.step_frame(
			Config.no_action_frame(reset_runner.state)
		)
		reset_runner_us.append(Time.get_ticks_usec() - started)
		reset_hashes.append(reset_result.hash if reset_result.ok else "")
	var record := {
		"schema": "package-2c-variant-profile-v1",
		"variant": variant,
		"continuous": true,
		"tuning": Tuning.VALUES,
		"tuning_hash": Tuning.canonical_hash(),
		"room_hash": room.room_hash.hex_encode(),
		"occupancy_hash": room.occupancy_hash.hex_encode(),
		"occupancy_bytes": room.occupancy_bytes.size(),
		"grid_cells": runner.state.settled_cells.size(),
		"initial_state_hash": initial_state_hash,
		"final_state_hash": Serializer.state_hash(runner.state),
		"final_tick": runner.state.tick,
		"core_simulation_us": core_us,
		"full_runner_us": runner_us,
		"checkpoint_hash_us": hash_us,
		"first_lane_report": first_report,
		"lanes_reached": Config.stress_lanes_reached(first_report),
		"resume_hash_identical": resume_identical,
		"replay_bytes": replay.bytes.size(),
		"replay_sha256": _sha256(replay.bytes),
		"replay_round_trip": decoded.ok and decoded.frames == frames,
		"reset_microbenchmark": {
			"continuous": false,
			"full_runner_us": reset_runner_us,
			"identical_hashes": reset_hashes[0] == reset_hashes[1],
			"hash": reset_hashes[0],
		},
	}
	print("P2C_VARIANT_PROFILE %s" % JSON.stringify(record))
	quit(0)


func _header(room: Dictionary, state: Dictionary) -> Dictionary:
	return {
		"project_commit_id": "ef307686b65b6bbd17253db5079b8886f3b554ee",
		"room_identifier": room.identifier,
		"room_definition_hash": room.room_hash,
		"tuning_hash": room.tuning_hash,
		"initial_ledger": state.ledger.duplicate(true),
		"initial_player": {
			"position_x_fp": state.player.position_x_fp,
			"position_y_fp": state.player.position_y_fp,
			"facing": state.player.facing,
		},
		"target_platform": "p2c-profile",
		"engine_version": "Godot 4.6.3",
	}


func _sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
