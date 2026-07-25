extends RefCounted

const Contracts := preload("res://better_spewing/contracts/goo_contracts.gd")
const Serializer := preload("res://better_spewing/contracts/canonical_serializer.gd")
const Schema := preload("res://better_spewing/contracts/canonical_state_schema.gd")
const MouthDerivation := preload("res://better_spewing/runner/mouth_derivation.gd")
const AimTable := preload("res://better_spewing/aim/aim_table.gd")
const GooSimulation := preload("res://better_spewing/simulation/goo_simulation.gd")

const AUTHORITATIVE_HZ := 60
const MICROSECONDS_PER_SECOND := 1_000_000

var state: Dictionary
var scheduler_units := 0
var checkpoint_hashes: Array[String] = []
var simulation: RefCounted
var initialization_error := ""


func _init(initial_state: Dictionary = {}, collision_context: Dictionary = {}) -> void:
	state = Schema.default_state() if initial_state.is_empty() else initial_state.duplicate(true)
	var table := AimTable.load_checked()
	simulation = GooSimulation.new(table.entries if table.ok else [])
	if not collision_context.is_empty():
		initialization_error = simulation.configure_room(state, collision_context)


func step_from_source(source: Variant) -> Dictionary:
	var command: Dictionary = source.next_frame(state.tick, state)
	if not command.ok:
		return {"ok": false, "error": command.error, "hash": ""}
	return step_frame(command.frame)


func step_frame(frame: Dictionary) -> Dictionary:
	if not initialization_error.is_empty():
		return {"ok": false, "error": initialization_error, "hash": Serializer.state_hash(state)}
	var error := Contracts.validate_command_frame(frame)
	if not error.is_empty():
		return {"ok": false, "error": error, "hash": ""}
	if frame.tick != state.tick:
		return {"ok": false, "error": "authoritative tick mismatch", "hash": ""}
	var mouth := MouthDerivation.derive(state.player)
	if frame.asserted_mouth_x_fp != mouth.x:
		return {"ok": false, "error": "authoritative mouth x mismatch", "hash": ""}
	if frame.asserted_mouth_y_fp != mouth.y:
		return {"ok": false, "error": "authoritative mouth y mismatch", "hash": ""}
	if frame.move_x != 0:
		state.player.facing = frame.move_x
	state.player.last_valid_aim = frame.aim_angle
	state.player.current_goo_action = frame.goo_action
	state.player.action_released = frame.goo_action == Contracts.GooAction.NONE
	state.command_sampler.last_tick = frame.tick
	state.command_sampler.last_move_x = frame.move_x
	state.command_sampler.last_move_y = frame.move_y
	state.command_sampler.jump_was_down = frame.jump_pressed
	state.command_sampler.spew_was_down = frame.goo_action == Contracts.GooAction.SPEW
	state.command_sampler.gulp_was_down = frame.goo_action == Contracts.GooAction.GULP
	state.command_sampler.resolved_action = frame.goo_action
	state.command_sampler.last_valid_aim = frame.aim_angle
	state.command_sampler.facing = state.player.facing
	var simulation_result: Dictionary = simulation.step(state, frame)
	if not simulation_result.get("ok", true):
		return {"ok": false, "error": simulation_result.error, "hash": Serializer.state_hash(state), "simulation": simulation_result}
	state.tick += 1
	var hash := Serializer.state_hash(state)
	if hash.is_empty():
		return {"ok": false, "error": Serializer.validate_state(state), "hash": ""}
	checkpoint_hashes.append(hash)
	return {"ok": true, "error": "", "hash": hash, "simulation": simulation_result}


func run_ticks(source: Variant, count: int) -> Dictionary:
	for unused in count:
		var result := step_from_source(source)
		if not result.ok:
			return result
	return {"ok": true, "error": "", "hash": Serializer.state_hash(state)}


func schedule_elapsed_microseconds(elapsed_us: int, source: Variant) -> Dictionary:
	if elapsed_us < 0:
		return {"ok": false, "error": "elapsed microseconds cannot be negative", "ticks": 0}
	scheduler_units += elapsed_us * AUTHORITATIVE_HZ
	var ticks := scheduler_units / MICROSECONDS_PER_SECOND
	scheduler_units %= MICROSECONDS_PER_SECOND
	var result := run_ticks(source, ticks)
	return {"ok": result.ok, "error": result.error, "ticks": ticks}


func drain_packet_checked(packet_id: int) -> Dictionary:
	var result: Dictionary = simulation.drain_packet(state, packet_id)
	if not result.ok:
		return {"ok": false, "error": result.error, "hash": Serializer.state_hash(state)}
	var hash := Serializer.state_hash(state)
	if hash.is_empty():
		return {"ok": false, "error": Serializer.validate_state(state), "hash": ""}
	return {"ok": true, "error": "", "hash": hash, "drain": result}
