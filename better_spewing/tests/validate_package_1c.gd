extends SceneTree

const Contracts := preload("res://better_spewing/contracts/goo_contracts.gd")
const Tuning := preload("res://better_spewing/contracts/goo_tuning.gd")
const Schema := preload("res://better_spewing/contracts/canonical_state_schema.gd")
const Serializer := preload("res://better_spewing/contracts/canonical_serializer.gd")
const AimTable := preload("res://better_spewing/aim/aim_table.gd")
const MouthDerivation := preload("res://better_spewing/runner/mouth_derivation.gd")
const Simulation := preload("res://better_spewing/simulation/goo_simulation.gd")
const Runner := preload("res://better_spewing/runner/authoritative_runner.gd")
const ReplayCodec := preload("res://better_spewing/replay/replay_codec.gd")
const Fixture := preload("res://better_spewing/tests/p1b_fixture_factory.gd")

var passed := 0
var failed := 0
var simulation: RefCounted
var directions: Array[Vector2i]


func _init() -> void:
	var table := AimTable.load_checked()
	_check(table.ok, "canonical aim resource loads")
	if not table.ok:
		_finish()
		return
	directions = table.entries
	simulation = Simulation.new(directions)
	_test_rate_and_release()
	_test_atomic_acceptance_and_ids()
	_test_id_exhaustion_atomicity()
	_test_coalescing_predicates()
	_test_recoil()
	_test_packet_integration_and_lifetime()
	_test_drain_fifo_and_partial_return()
	_test_hundred_conserved_cycles()
	_test_packet_cap_stress()
	_test_replay_and_schema()
	_test_visualization_scene()
	_finish()


func _test_rate_and_release() -> void:
	var state := _state_with_reserve(1600)
	var expected_remainder := 0
	var expected_total := 0
	var actual_sequence: Array[int] = []
	var exact := true
	for tick in 60:
		state.tick = tick
		var expected_accumulated := expected_remainder + 448
		var expected_amount: int = expected_accumulated / 60
		expected_remainder = expected_accumulated % 60
		expected_total += expected_amount
		var result: Dictionary = simulation.accept_spew(state, _frame(state, Contracts.GooAction.SPEW, tick % 4096))
		actual_sequence.append(result.accepted_q)
		exact = exact and result.accepted_q == expected_amount
		exact = exact and state.command_sampler.spew_rate_remainder == expected_remainder
	_check(exact, "all 60 integer spew-rate outputs and remainders match 448/60")
	_check(expected_total == 448 and _sum_ints(actual_sequence) == 448, "60-tick spew sequence totals exactly 448 quanta")
	var release_state := _state_with_reserve(1600)
	release_state.command_sampler.spew_rate_remainder = 59
	simulation.step(release_state, _frame(release_state, Contracts.GooAction.NONE, 0))
	_check(release_state.command_sampler.spew_rate_remainder == 0, "spew fractional remainder resets on release")
	var resumed: Dictionary = simulation.accept_spew(release_state, _frame(release_state, Contracts.GooAction.SPEW, 0))
	_check(resumed.accepted_q == 7 and release_state.command_sampler.spew_rate_remainder == 28, "new press starts without fractional carry")
	var rejected_cadence := _state_with_reserve(0)
	rejected_cadence.ledger.initial = 1600
	rejected_cadence.ledger.drain = 1600
	var rejected_remainders: Array[int] = []
	for tick in 5:
		rejected_cadence.tick = tick
		var rejected: Dictionary = simulation.accept_spew(rejected_cadence, _frame(rejected_cadence, Contracts.GooAction.SPEW, 0))
		rejected_remainders.append(rejected_cadence.command_sampler.spew_rate_remainder)
		_check(rejected.rejected and rejected.accepted_q == 0, "held spew rejection owns no volume at cadence tick %d" % tick)
	_check(rejected_remainders == [28, 56, 24, 52, 20], "held rejected ticks advance canonical 448/60 rate remainders")
	rejected_cadence.ledger.reserve = 1600
	rejected_cadence.ledger.drain = 0
	rejected_cadence.tick = 5
	var freed_first: Dictionary = simulation.accept_spew(rejected_cadence, _frame(rejected_cadence, Contracts.GooAction.SPEW, 0))
	rejected_cadence.tick = 6
	var freed_second: Dictionary = simulation.accept_spew(rejected_cadence, _frame(rejected_cadence, Contracts.GooAction.SPEW, 0))
	_check(freed_first.accepted_q == 7 and freed_second.accepted_q == 8 and rejected_cadence.command_sampler.spew_rate_remainder == 16, "capacity-free ticks resume canonical cadence without frozen or banked output")
	simulation.step(rejected_cadence, _frame(rejected_cadence, Contracts.GooAction.NONE, 0))
	_check(rejected_cadence.command_sampler.spew_rate_remainder == 0, "release resets progressed rejection cadence")


func _test_atomic_acceptance_and_ids() -> void:
	var state := _state_with_reserve(1600)
	state.player.velocity_x_fp_per_s = 101
	state.player.velocity_y_fp_per_s = -99
	var velocity_before := Vector2i(state.player.velocity_x_fp_per_s, state.player.velocity_y_fp_per_s)
	var result: Dictionary = simulation.accept_spew(state, _frame(state, Contracts.GooAction.SPEW, 0))
	_check(result.accepted_q == 7 and result.created and result.packet_id == 1, "first accepted spew creates stable packet ID 1")
	_check(state.ledger.reserve == 1593 and state.ledger.airborne == 7 and _ledger_error(state) == 0, "debit and airborne credit are atomic after acceptance")
	_check(state.packets[0].position_x_fp == MouthDerivation.derive(state.player).x and state.packets[0].position_y_fp == MouthDerivation.derive(state.player).y, "packet spawns at authoritative derived mouth")
	_check(state.packets[0].velocity_x_fp_per_s == Tuning.VALUES.packet_launch_speed_fp_per_s + 50, "packet inherits exact integer 50 percent player x velocity")
	_check(state.packets[0].velocity_y_fp_per_s == -49, "negative 50 percent velocity inheritance truncates deterministically toward zero")
	_check(Vector2i(state.player.velocity_x_fp_per_s, state.player.velocity_y_fp_per_s) == velocity_before, "accepted recoil does not alter player velocity")
	state.tick = 1
	result = simulation.accept_spew(state, _frame(state, Contracts.GooAction.SPEW, 1024))
	_check(result.created and result.packet_id == 2 and state.next_ids.packet == 3, "new packets consume monotonic nonzero IDs without reuse")
	var limited := _state_with_reserve(3)
	var limited_result: Dictionary = simulation.accept_spew(limited, _frame(limited, Contracts.GooAction.SPEW, 0))
	_check(limited_result.accepted_q == 3 and limited.ledger.reserve == 0 and limited.ledger.airborne == 3, "reserve shortage accepts and debits only the exact available amount")
	var empty := _state_with_reserve(0)
	var empty_before: Dictionary = empty.duplicate(true)
	var empty_result: Dictionary = simulation.accept_spew(empty, _frame(empty, Contracts.GooAction.SPEW, 0))
	_check(empty_result.rejected and _equal_except_spew_rate(empty_before, empty), "empty reserve rejection changes only canonical held-input rate progression")
	_check(empty.command_sampler.spew_rate_remainder == 28, "empty reserve rejection advances spew rate remainder")

	var rejected := _full_cap_state()
	rejected.command_sampler.spew_rate_remainder = 17
	rejected.remainders.recoil_fraction = 3
	rejected.remainders.player_recoil_x = 123
	rejected.remainders.player_recoil_y = -456
	rejected.player.recoil_x_fp_per_s = 9
	rejected.player.recoil_y_fp_per_s = -8
	rejected.packets[-1].aim_angle = 5
	var before: Dictionary = rejected.duplicate(true)
	var rejection: Dictionary = simulation.accept_spew(rejected, _frame(rejected, Contracts.GooAction.SPEW, 6))
	_check(rejection.rejected and rejection.accepted_q == 0, "incompatible cap request rejects before acceptance")
	_check(_equal_except_spew_rate(before, rejected), "rejection leaves ledger, IDs, packets, recoil, and non-rate remainders byte-identical")
	_check(rejected.command_sampler.spew_rate_remainder == 45, "cap rejection advances held-input rate remainder")


func _test_coalescing_predicates() -> void:
	var compatible := _full_cap_state()
	compatible.tick = 10
	var newest: Dictionary = compatible.packets[-1]
	newest.emission_tick = 9
	newest.aim_angle = 700
	newest.position_x_fp = MouthDerivation.derive(compatible.player).x
	newest.position_y_fp = MouthDerivation.derive(compatible.player).y
	newest.volume_q = 1
	_reconcile_cap_ledger(compatible)
	var next_id_before: int = compatible.next_ids.packet
	var merge: Dictionary = simulation.accept_spew(compatible, _frame(compatible, Contracts.GooAction.SPEW, 700))
	_check(merge.merged and merge.accepted_q == 7 and compatible.packets.size() == 192, "compatible newest packet coalesces at cap")
	_check(compatible.next_ids.packet == next_id_before and merge.packet_id == newest.id, "merge consumes no new stable ID")

	var predicates := [
		["preceding tick", func(state: Dictionary) -> void: state.packets[-1].emission_tick = state.tick - 2],
		["same quantized aim", func(state: Dictionary) -> void: state.packets[-1].aim_angle = 701],
		["within mouth cell", func(state: Dictionary) -> void: state.packets[-1].position_x_fp += Tuning.VALUES.grid_cell_size_px * 256 + 1],
		["airborne lifecycle", func(state: Dictionary) -> void: state.packets[-1].lifecycle = Contracts.PacketLifecycle.STATIONARY_DEPOSITION],
		["not suction reserved", func(state: Dictionary) -> void: state.packets[-1].suction_reserved = true],
		["not collided", func(state: Dictionary) -> void: state.packets[-1].stationary_ticks = 1],
		["merge volume capacity", func(state: Dictionary) -> void: state.packets[-1].volume_q = Tuning.VALUES.maximum_packet_volume_q],
	]
	for predicate in predicates:
		var state := _compatible_cap_state()
		predicate[1].call(state)
		_reconcile_cap_ledger(state)
		var before: Dictionary = state.duplicate(true)
		var result: Dictionary = simulation.accept_spew(state, _frame(state, Contracts.GooAction.SPEW, 700))
		_check(result.rejected and _equal_except_spew_rate(before, state), "coalescing rejection changes only rate progression when predicate fails: %s" % predicate[0])

	var partial := _compatible_cap_state()
	partial.packets[-1].volume_q = 14
	_reconcile_cap_ledger(partial)
	var reserve_before: int = partial.ledger.reserve
	var id_before: int = partial.next_ids.packet
	var partial_result: Dictionary = simulation.accept_spew(partial, _frame(partial, Contracts.GooAction.SPEW, 700))
	_check(partial_result.merged and partial_result.accepted_q == 2 and partial.packets[-1].volume_q == 16, "cap merge accepts exactly available two-quanta capacity")
	_check(partial.ledger.reserve == reserve_before - 2 and partial.next_ids.packet == id_before and _ledger_error(partial) == 0, "partial cap acceptance debits only accepted amount with no ID")


func _test_id_exhaustion_atomicity() -> void:
	var all_exhausted := Schema.default_state()
	for id_namespace in all_exhausted.next_ids:
		all_exhausted.next_ids[id_namespace] = Contracts.INVALID_STABLE_ID
	_check(Serializer.serialize_state_checked(all_exhausted).ok, "all canonical next-ID namespaces serialize explicit zero exhaustion sentinels")
	_check(not Contracts.consume_stable_id(Contracts.INVALID_STABLE_ID).ok, "exhausted namespace cannot allocate or reuse ID zero")

	var packet_state := _state_with_reserve(1600)
	packet_state.next_ids.packet = Contracts.MAX_STABLE_ID
	var packet_runner := Runner.new(packet_state)
	var final_allocation: Dictionary = packet_runner.step_frame(_frame(packet_runner.state, Contracts.GooAction.SPEW, 0))
	_check(final_allocation.ok and final_allocation.simulation.created, "runner succeeds while allocating terminal packet ID 0xffffffff")
	_check(packet_runner.state.packets[-1].id == Contracts.MAX_STABLE_ID and packet_runner.state.next_ids.packet == Contracts.INVALID_STABLE_ID, "terminal packet allocation stores nonzero max ID and explicit exhausted next-ID")
	_check(not final_allocation.hash.is_empty() and Serializer.serialize_state_checked(packet_runner.state).ok, "terminal packet allocation leaves hash-valid canonical state")
	packet_runner.state.packets[-1].lifecycle = Contracts.PacketLifecycle.STATIONARY_DEPOSITION
	packet_runner.state.packets[-1].stationary_ticks = 1
	packet_runner.state.player.recoil_x_fp_per_s = 0
	packet_runner.state.player.recoil_y_fp_per_s = 0
	var ledger_before: Dictionary = packet_runner.state.ledger.duplicate(true)
	var packets_before: Array = packet_runner.state.packets.duplicate(true)
	var recoil_remainders := Vector3i(packet_runner.state.remainders.player_recoil_x, packet_runner.state.remainders.player_recoil_y, packet_runner.state.remainders.recoil_fraction)
	var velocity_before := Vector2i(packet_runner.state.player.velocity_x_fp_per_s, packet_runner.state.player.velocity_y_fp_per_s)
	var exhausted_attempt: Dictionary = packet_runner.step_frame(_frame(packet_runner.state, Contracts.GooAction.SPEW, 0))
	_check(exhausted_attempt.ok and exhausted_attempt.simulation.rejected, "runner reports later exhausted packet creation as a hash-valid rejected action")
	_check(packet_runner.state.ledger == ledger_before and packet_runner.state.packets == packets_before and packet_runner.state.next_ids.packet == 0, "exhausted runner rejection leaves ledger, packets, and packet namespace untouched")
	_check(Vector3i(packet_runner.state.remainders.player_recoil_x, packet_runner.state.remainders.player_recoil_y, packet_runner.state.remainders.recoil_fraction) == recoil_remainders and Vector2i(packet_runner.state.player.velocity_x_fp_per_s, packet_runner.state.player.velocity_y_fp_per_s) == velocity_before, "exhausted runner rejection leaves recoil remainders and player velocity untouched")
	_check(packet_runner.state.command_sampler.spew_rate_remainder == 56, "exhausted runner rejection still advances held-input rate cadence")

	var drain_state := _state_with_reserve(1580)
	drain_state.ledger.initial = 1600
	drain_state.ledger.airborne = 20
	drain_state.packets = [_packet(1, 10), _packet(2, 10)]
	drain_state.next_ids.packet = 3
	drain_state.next_ids.drain_record = Contracts.MAX_STABLE_ID
	var drain_runner := Runner.new(drain_state)
	var final_drain: Dictionary = drain_runner.drain_packet_checked(1)
	_check(final_drain.ok and drain_runner.state.drain_queue[-1].id == Contracts.MAX_STABLE_ID and drain_runner.state.next_ids.drain_record == 0, "runner drain API allocates terminal record ID and records exhaustion")
	_check(not final_drain.hash.is_empty() and Serializer.serialize_state_checked(drain_runner.state).ok, "terminal drain allocation leaves hash-valid canonical state")
	var drain_before := Serializer.serialize_state_checked(drain_runner.state)
	var rejected_drain: Dictionary = drain_runner.drain_packet_checked(2)
	var drain_after := Serializer.serialize_state_checked(drain_runner.state)
	_check(not rejected_drain.ok and "exhausted" in rejected_drain.error, "later drain allocation rejects explicit exhausted namespace")
	_check(drain_before.ok and drain_after.ok and drain_before.bytes == drain_after.bytes and drain_runner.state.packets[0].id == 2, "exhausted drain rejection leaves source packet and all canonical state untouched")


func _test_recoil() -> void:
	var cardinal := _state_with_reserve(1600)
	var right: Vector2i = simulation.compute_recoil(cardinal, 5, 0)
	_check(right == Vector2i(-1536, 0), "five-quanta rightward spew returns exact cardinal -1536 x recoil")
	var downward_state := _state_with_reserve(1600)
	var down: Vector2i = simulation.compute_recoil(downward_state, 5, 1024)
	_check(down == Vector2i(0, -1536), "five-quanta downward spew returns exact upward cardinal recoil")
	var diagonal := _state_with_reserve(1600)
	var direction: Vector2i = directions[512]
	var diagonal_result: Vector2i = simulation.compute_recoil(diagonal, 1, 512)
	var magnitude := 307
	var x_total: int = -direction.x * magnitude
	var y_total: int = -direction.y * magnitude
	var expected_x: int = _divide_trunc(x_total, 1_000_000)
	var expected_y: int = _divide_trunc(y_total, 1_000_000)
	_check(diagonal_result == Vector2i(expected_x, expected_y), "non-cardinal recoil uses exact lookup direction")
	_check(diagonal.remainders.recoil_fraction == 1 and diagonal.remainders.player_recoil_x == x_total - expected_x * 1_000_000 and diagonal.remainders.player_recoil_y == y_total - expected_y * 1_000_000, "rational and direction recoil remainders are canonical and exact")
	var capped := _state_with_reserve(1600)
	var capped_result: Vector2i = simulation.compute_recoil(capped, 16, 2048)
	_check(capped_result == Vector2i(4096, 0), "recoil magnitude caps exactly at 16 px/s per tick")

	var rejected := _full_cap_state()
	rejected.packets[-1].aim_angle = 1
	var velocity := Vector2i(rejected.player.velocity_x_fp_per_s, rejected.player.velocity_y_fp_per_s)
	var recoil_remainders := Vector3i(rejected.remainders.player_recoil_x, rejected.remainders.player_recoil_y, rejected.remainders.recoil_fraction)
	var result: Dictionary = simulation.accept_spew(rejected, _frame(rejected, Contracts.GooAction.SPEW, 2))
	_check(result.rejected and Vector2i(rejected.player.recoil_x_fp_per_s, rejected.player.recoil_y_fp_per_s) == Vector2i.ZERO, "rejected spew returns zero recoil")
	_check(Vector2i(rejected.player.velocity_x_fp_per_s, rejected.player.velocity_y_fp_per_s) == velocity and Vector3i(rejected.remainders.player_recoil_x, rejected.remainders.player_recoil_y, rejected.remainders.recoil_fraction) == recoil_remainders, "rejection changes neither player velocity nor recoil remainders")


func _test_packet_integration_and_lifetime() -> void:
	var state := _state_with_reserve(1590)
	state.ledger.initial = 1600
	state.ledger.airborne = 10
	state.packets.append(_packet(1, 10))
	state.packets[0].velocity_x_fp_per_s = 61
	state.packets[0].velocity_y_fp_per_s = 0
	state.packets[0].lifetime_ticks = 2
	state.next_ids.packet = 2
	simulation.integrate_packets(state)
	var packet: Dictionary = state.packets[0]
	_check(packet.position_x_fp == 1 and packet.position_x_remainder == 1, "x position integration preserves exact subpixel remainder")
	_check(packet.velocity_y_fp_per_s == 6400 and packet.position_y_fp == 106 and packet.position_y_remainder == 40, "gravity and y position integrate deterministically at 60 Hz")
	_check(packet.lifetime_ticks == 1, "packet lifetime is remaining future travel integrations")
	state.tick = 1
	simulation.integrate_packets(state)
	_check(state.packets.is_empty() and state.ledger.airborne == 0 and state.ledger.drain == 10, "lifetime expiry atomically transfers full packet volume to DRAIN")
	_check(state.drain_queue.size() == 1 and state.drain_queue[0].amount_q == 10 and state.drain_queue[0].return_tick == 91, "expiry creates one delayed drain record without loss")


func _test_drain_fifo_and_partial_return() -> void:
	var state := _state_with_reserve(1598)
	state.ledger.initial = 1608
	state.ledger.airborne = 10
	state.packets.append(_packet(1, 10))
	state.next_ids.packet = 2
	state.tick = 5
	var drained: Dictionary = simulation.drain_packet(state, 1)
	_check(drained.ok and state.ledger.airborne == 0 and state.ledger.drain == 10 and _ledger_error(state) == 0, "explicit drain trigger transfers packet atomically")
	_check(state.drain_queue[0].return_tick == 95 and state.drain_queue[0].id == 1, "drain record uses stable ID and current tick plus 90")
	state.tick = 94
	_check(simulation.process_drain_returns(state) == 0 and state.ledger.drain == 10, "drain does not return before its declared tick")
	state.tick = 95
	_check(simulation.process_drain_returns(state) == 2 and state.drain_queue[0].amount_q == 8, "drain return partially fills free reserve capacity")
	_check(state.drain_queue[0].id == 1 and state.drain_queue[0].lifecycle == Contracts.DrainLifecycle.RETURN_READY, "partial drain remainder stays in the same FIFO record")
	state.ledger.reserve = 1590
	state.ledger.settled = 10
	_check(simulation.process_drain_returns(state) == 8 and state.drain_queue.is_empty(), "remaining drain volume returns from FIFO when capacity becomes free")
	_check(_ledger_error(state) == 0, "partial and delayed drain returns conserve ledger")

	var fifo := _state_with_reserve(1595)
	fifo.ledger.initial = 1615
	fifo.ledger.airborne = 20
	fifo.packets = [_packet(1, 10), _packet(2, 10)]
	fifo.next_ids.packet = 3
	simulation.drain_packet(fifo, 1)
	simulation.drain_packet(fifo, 2)
	fifo.tick = 90
	_check(simulation.process_drain_returns(fifo) == 5, "FIFO drain processing uses only current reserve capacity")
	_check(fifo.drain_queue.size() == 2 and fifo.drain_queue[0].id == 1 and fifo.drain_queue[0].amount_q == 5 and fifo.drain_queue[1].id == 2 and fifo.drain_queue[1].amount_q == 10, "partial first drain record blocks later FIFO records without reordering")
	_check(_ledger_error(fifo) == 0, "multi-record FIFO partial return conserves ledger")


func _test_hundred_conserved_cycles() -> void:
	var state := _state_with_reserve(1600)
	var conserved := true
	for cycle in 100:
		state.command_sampler.spew_rate_remainder = 0
		var emission: Dictionary = simulation.accept_spew(state, _frame(state, Contracts.GooAction.SPEW, cycle % 4096))
		conserved = conserved and emission.accepted_q == 7 and _ledger_error(state) == 0
		var drained: Dictionary = simulation.drain_packet(state, emission.packet_id)
		conserved = conserved and drained.ok and _ledger_error(state) == 0
		var return_tick: int = state.drain_queue[0].return_tick
		while state.tick < return_tick:
			state.tick += 1
			simulation.process_drain_returns(state)
			conserved = conserved and _ledger_error(state) == 0
		conserved = conserved and state.drain_queue.is_empty()
	_check(conserved, "100 emission-to-drain-to-delayed-return cycles have zero ledger error at every tick")
	_check(state.ledger.reserve == 1600 and state.ledger.airborne == 0 and state.ledger.drain == 0 and state.packets.is_empty(), "100-cycle final category totals return exactly to reserve")
	_check(state.next_ids.packet == 101 and state.next_ids.drain_record == 101, "100 cycles preserve monotonic packet and drain IDs without reuse")


func _test_packet_cap_stress() -> void:
	var state := _compatible_cap_state()
	state.packets[-1].volume_q = 1
	_reconcile_cap_ledger(state)
	var conserved := true
	var accepted: Array[int] = []
	for tick in [10, 11, 12]:
		state.tick = tick
		state.packets[-1].emission_tick = tick - 1
		var result: Dictionary = simulation.accept_spew(state, _frame(state, Contracts.GooAction.SPEW, 700))
		accepted.append(result.accepted_q)
		conserved = conserved and _ledger_error(state) == 0 and state.packets.size() == 192
	state.tick = 13
	state.packets[-1].emission_tick = 12
	var before: Dictionary = state.duplicate(true)
	var rejected: Dictionary = simulation.accept_spew(state, _frame(state, Contracts.GooAction.SPEW, 700))
	_check(accepted == [7, 7, 1] and state.packets[-1].volume_q == 16, "cap stress coalesces 15 quanta only up to exact packet capacity")
	_check(rejected.rejected and _equal_except_spew_rate(before, state), "full merged packet rejection advances only rate state")
	_check(conserved and _ledger_error(state) == 0 and _packet_volume(state) == state.ledger.airborne, "packet cap stress has zero volume loss")


func _test_replay_and_schema() -> void:
	var encoded := ReplayCodec.encode(Fixture.header(), Fixture.frames())
	var decoded := ReplayCodec.decode(encoded.bytes, Fixture.header())
	var reencoded := ReplayCodec.encode(decoded.header, decoded.frames) if decoded.ok else {"ok": false, "bytes": PackedByteArray()}
	_check(encoded.ok and decoded.ok and reencoded.ok and reencoded.bytes == encoded.bytes, "Package 1C replay commands retain exact byte round-trip")
	var old := Schema.default_state()
	old.schema_version = 1
	_check(not Serializer.serialize_state_checked(old).ok, "canonical serializer rejects pre-1C schema version 1")
	_check(Schema.FIELD_ORDER.has("packet.emission_tick:u32") and Schema.FIELD_ORDER.has("packet.aim_angle:u16"), "schema declares serialized coalescing tick and aim")
	var packet_state := Schema.default_state()
	packet_state.ledger.initial = 1
	packet_state.ledger.airborne = 1
	var packet := Schema.default_packet()
	packet.id = 0x01020304
	packet.emission_tick = 0x0a0b0c0d
	packet.aim_angle = 0x0102
	packet_state.packets = [packet]
	packet_state.next_ids.packet = 0x01020305
	var serialized := Serializer.serialize_state_checked(packet_state)
	_check(serialized.ok and serialized.bytes.slice(66, 76).hex_encode() == "040302010d0c0b0a0201", "packet ID, emission tick, and aim have locked little-endian widths and order")
	packet_state.packets[0].aim_angle = 4096
	_check(not Serializer.serialize_state_checked(packet_state).ok, "out-of-range serialized packet aim is rejected")


func _test_visualization_scene() -> void:
	var packed := load("res://better_spewing/visualization/isolated_packet_simulation.tscn")
	var scene_ok := packed is PackedScene
	var instance: Node = packed.instantiate() if scene_ok else null
	if instance != null:
		instance._ready()
	var visualizer: Node = instance.get_node("PacketVisualizer") if instance != null else null
	var sequence_ok: bool = (
		instance != null
		and instance.authoritative_snapshots.size() == 3
		and not instance.authoritative_snapshots[0].is_empty()
		and instance.authoritative_snapshots[0][0].position_x_fp
			!= instance.authoritative_snapshots[1][0].position_x_fp
		and instance.authoritative_snapshots[1][0].position_x_fp
			!= instance.authoritative_snapshots[2][0].position_x_fp
	)
	_check(scene_ok and visualizer != null and sequence_ok, "isolated scene advances real authoritative packet positions over three fixed ticks")
	_check(visualizer != null and visualizer.packet_snapshot == instance.runner.state.packets, "render snapshot exactly matches authoritative packet snapshot before drawing")
	var state_position_before: int = instance.runner.state.packets[0].position_x_fp if instance != null else 0
	var state_hash_before: String = instance.authoritative_hash_before_render if instance != null else ""
	if visualizer != null:
		visualizer.packet_snapshot[0].position_x_fp += 999
	_check(instance != null and instance.runner.state.packets[0].position_x_fp == state_position_before, "render-side packet mutation cannot flow back into authoritative state")
	_check(instance != null and Serializer.state_hash(instance.runner.state) == state_hash_before, "render-side mutation cannot change authoritative complete-state hash")
	if instance != null:
		instance.free()


func _state_with_reserve(reserve_q: int) -> Dictionary:
	var state := Schema.default_state()
	state.ledger.initial = reserve_q
	state.ledger.reserve = reserve_q
	return state


func _packet(id: int, volume_q: int) -> Dictionary:
	return {
		"id": id,
		"emission_tick": 0,
		"aim_angle": 0,
		"position_x_fp": 0,
		"position_y_fp": 0,
		"velocity_x_fp_per_s": 0,
		"velocity_y_fp_per_s": 0,
		"volume_q": volume_q,
		"lifetime_ticks": Tuning.VALUES.packet_lifetime_ticks,
		"lifecycle": Contracts.PacketLifecycle.AIRBORNE,
		"suction_reserved": false,
		"stationary_ticks": 0,
		"position_x_remainder": 0,
		"position_y_remainder": 0,
		"gravity_remainder": 0,
	}


func _full_cap_state() -> Dictionary:
	var state := Schema.default_state()
	for id in range(1, Tuning.VALUES.maximum_airborne_packets + 1):
		state.packets.append(_packet(id, 1))
	state.next_ids.packet = Tuning.VALUES.maximum_airborne_packets + 1
	_reconcile_cap_ledger(state)
	return state


func _compatible_cap_state() -> Dictionary:
	var state := _full_cap_state()
	state.tick = 10
	var newest: Dictionary = state.packets[-1]
	newest.emission_tick = 9
	newest.aim_angle = 700
	var mouth := MouthDerivation.derive(state.player)
	newest.position_x_fp = mouth.x
	newest.position_y_fp = mouth.y
	newest.volume_q = 1
	_reconcile_cap_ledger(state)
	return state


func _reconcile_cap_ledger(state: Dictionary) -> void:
	var airborne := _packet_volume(state)
	state.ledger.initial = 1600
	state.ledger.airborne = airborne
	state.ledger.reserve = 1600 - airborne


func _frame(state: Dictionary, action: int, aim: int) -> Dictionary:
	var mouth := MouthDerivation.derive(state.player)
	return {
		"tick": state.tick,
		"move_x": 0,
		"move_y": 0,
		"jump_pressed": false,
		"goo_action": action,
		"aim_angle": aim,
		"asserted_mouth_x_fp": mouth.x,
		"asserted_mouth_y_fp": mouth.y,
	}


func _ledger_error(state: Dictionary) -> int:
	return state.ledger.initial - Contracts.ledger_total(state.ledger)


func _packet_volume(state: Dictionary) -> int:
	var total := 0
	for packet in state.packets:
		total += packet.volume_q
	return total


func _sum_ints(values: Array[int]) -> int:
	var total := 0
	for value in values:
		total += value
	return total


func _divide_trunc(numerator: int, denominator: int) -> int:
	if numerator >= 0:
		return numerator / denominator
	return -((-numerator) / denominator)


func _equal_except_spew_rate(before: Dictionary, after: Dictionary) -> bool:
	var normalized: Dictionary = after.duplicate(true)
	normalized.command_sampler.spew_rate_remainder = before.command_sampler.spew_rate_remainder
	var before_bytes := Serializer.serialize_state_checked(before)
	var after_bytes := Serializer.serialize_state_checked(normalized)
	return before_bytes.ok and after_bytes.ok and before_bytes.bytes == after_bytes.bytes


func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		printerr("FAIL: %s" % label)


func _finish() -> void:
	print("P1C_SUITE passed=%d failed=%d result=%s" % [passed, failed, "PASS" if failed == 0 else "FAIL"])
	quit(0 if failed == 0 else 1)
