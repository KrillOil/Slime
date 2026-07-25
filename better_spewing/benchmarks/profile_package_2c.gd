extends SceneTree

const Serializer := preload("res://better_spewing/contracts/canonical_serializer.gd")
const Deposition := preload("res://better_spewing/deposition/settled_deposition.gd")
const Flow := preload("res://better_spewing/flow/settled_flow.gd")
const Config := preload("res://better_spewing/benchmarks/flow_benchmark_config.gd")

const PROFILE_SAMPLES := 5


func _init() -> void:
	var stress := Config.build_stress_runner()
	var runner: RefCounted = stress.runner
	var template: Dictionary = stress.template
	var room: Dictionary = Config.room_context("package-2c-stress")
	var timings := {
		"deep_copy_us": [],
		"deposition_us": [],
		"flow_us": [],
		"state_hash_us": [],
		"full_runner_tick_us": [],
	}
	for unused in PROFILE_SAMPLES:
		var start := Time.get_ticks_usec()
		var working: Dictionary = template.duplicate(true)
		timings.deep_copy_us.append(Time.get_ticks_usec() - start)

		start = Time.get_ticks_usec()
		var deposition: Dictionary = Deposition.process_stationary_packets(
			working,
			room
		)
		timings.deposition_us.append(Time.get_ticks_usec() - start)
		if not deposition.ok:
			_fail("deposition profile failed: %s" % deposition.error)
			return

		start = Time.get_ticks_usec()
		var flow: Dictionary = Flow.step(working, room)
		timings.flow_us.append(Time.get_ticks_usec() - start)
		if not flow.ok:
			_fail("flow profile failed: %s" % flow.error)
			return

		start = Time.get_ticks_usec()
		var hash := Serializer.state_hash(working)
		timings.state_hash_us.append(Time.get_ticks_usec() - start)
		if hash.is_empty():
			_fail("state hash profile failed")
			return

		runner.state = template.duplicate(true)
		runner.checkpoint_hashes.clear()
		start = Time.get_ticks_usec()
		var result: Dictionary = runner.step_frame(Config.no_action_frame(runner.state))
		timings.full_runner_tick_us.append(Time.get_ticks_usec() - start)
		if not result.ok:
			_fail("runner profile failed: %s" % result.error)
			return
	print("P2C_PROFILE %s" % JSON.stringify({
		"schema": "package-2c-flow-profile-v1",
		"samples": PROFILE_SAMPLES,
		"timings": timings,
		"median_us": {
			"deep_copy": _median(timings.deep_copy_us),
			"deposition": _median(timings.deposition_us),
			"flow": _median(timings.flow_us),
			"state_hash": _median(timings.state_hash_us),
			"full_runner_tick": _median(timings.full_runner_tick_us),
		},
	}))
	quit(0)


func _median(values: Array) -> int:
	var ordered := values.duplicate()
	ordered.sort()
	return ordered[ordered.size() / 2]


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
