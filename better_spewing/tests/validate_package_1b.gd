extends SceneTree

const AimTable := preload("res://better_spewing/aim/aim_table.gd")
const AimQuantizer := preload("res://better_spewing/aim/aim_quantizer.gd")
const Contracts := preload("res://better_spewing/contracts/goo_contracts.gd")
const Serializer := preload("res://better_spewing/contracts/canonical_serializer.gd")
const LiveSource := preload("res://better_spewing/runner/live_command_source.gd")
const ReplayCodec := preload("res://better_spewing/replay/replay_codec.gd")
const ReplaySource := preload("res://better_spewing/replay/replay_command_source.gd")
const Runner := preload("res://better_spewing/runner/authoritative_runner.gd")
const Fixture := preload("res://better_spewing/tests/p1b_fixture_factory.gd")

var passed := 0
var failed := 0
var entries: Array[Vector2i]


func _init() -> void:
	var table := AimTable.load_checked()
	_check(table.ok, "checked-in aim table loads with runtime checksum")
	if table.ok:
		entries = table.entries
		_test_aim_table()
		_test_aim_resolution()
		_test_live_replay_equivalence()
	_test_replay_codec()
	_test_mouth_assertions()
	_test_runner()
	print("P1B_SUITE passed=%d failed=%d result=%s" % [passed, failed, "PASS" if failed == 0 else "FAIL"])
	quit(0 if failed == 0 else 1)


func _test_aim_table() -> void:
	_check(entries.size() == 4096, "aim table has 4096 entries")
	_check(AimTable.BYTE_LENGTH == 32780, "aim table fixed byte length")
	_check(AimTable.SHA256 == "cd57fcdb178d685bf3ba4b07d37244fda27a8ebe802b7faa43d17b690e0e444b", "aim table SHA-256 fixture")
	_check(entries[0] == Vector2i(1000000, 0), "zero angle is positive x cardinal")
	_check(entries[1024] == Vector2i(0, 1000000), "quarter turn is positive y cardinal")
	_check(entries[2048] == Vector2i(-1000000, 0), "half turn is negative x cardinal")
	_check(entries[3072] == Vector2i(0, -1000000), "three-quarter turn is negative y cardinal")
	for index in [1, 127, 511, 1023]:
		_check(entries[2048 - index] == Vector2i(-entries[index].x, entries[index].y), "quadrant-II symmetry %d" % index)
		_check(entries[2048 + index] == -entries[index], "opposite-direction symmetry %d" % index)
		_check(entries[4096 - index] == Vector2i(entries[index].x, -entries[index].y), "quadrant-IV symmetry %d" % index)
	_check(AimQuantizer.wrap_index(-1) == 4095, "negative aim index wraps")
	_check(AimQuantizer.wrap_index(4096) == 0, "upper aim index wraps")
	_check(AimQuantizer.quantize_vector(100, 0, entries) == 0, "positive x quantizes to zero")
	_check(AimQuantizer.quantize_vector(0, 100, entries) == 1024, "positive y quantizes to quarter turn")


func _test_aim_resolution() -> void:
	var mouth := Vector2i(1000, 2000)
	_check(AimQuantizer.resolve(1000, 2000, mouth, false, 77, 1, entries) == 0, "near cursor without history uses right facing")
	_check(AimQuantizer.resolve(1000, 2000, mouth, false, 77, -1, entries) == 2048, "near cursor without history uses left facing")
	_check(AimQuantizer.resolve(1000 + 7 * 256, 2000, mouth, true, 77, 1, entries) == 77, "cursor below 8 px reuses last valid aim")
	_check(AimQuantizer.resolve(1000 + 8 * 256, 2000, mouth, true, 77, 1, entries) == 0, "cursor at 8 px quantizes a new aim")


func _test_replay_codec() -> void:
	var bytes := Fixture.replay_bytes()
	_check(bytes.size() == ReplayCodec.HEADER_BYTES + Fixture.frames().size() * ReplayCodec.COMMAND_BYTES, "replay has canonical fixed width")
	var decoded := ReplayCodec.decode(bytes, Fixture.header())
	_check(decoded.ok, "replay decodes with matching immutable header")
	if decoded.ok:
		var reencoded := ReplayCodec.encode(decoded.header, decoded.frames)
		_check(reencoded.ok and reencoded.bytes == bytes, "replay byte round-trip is exact")
	var bad := bytes.duplicate()
	bad[4] = 2
	_check(not ReplayCodec.decode(bad).ok, "unsupported replay version is rejected")
	_check(not ReplayCodec.decode(bytes.slice(0, bytes.size() - 1)).ok, "truncated replay is rejected")
	bad = bytes.duplicate()
	bad.append(0)
	_check(not ReplayCodec.decode(bad).ok, "extra replay data is rejected")
	bad = bytes.duplicate()
	bad[ReplayCodec.HEADER_BYTES + ReplayCodec.COMMAND_BYTES] = 9
	_check(not ReplayCodec.decode(bad).ok, "non-contiguous command ticks are rejected")
	bad = bytes.duplicate()
	bad[ReplayCodec.HEADER_BYTES + 6] = 2
	_check(not ReplayCodec.decode(bad).ok, "non-canonical command boolean is rejected")
	var mismatch := {"room_identifier": "different-room"}
	_check("header mismatch" in ReplayCodec.decode(bytes, mismatch).error, "immutable header mismatch is rejected")
	var malformed_header := Fixture.header()
	malformed_header.project_commit_id = "not-a-commit"
	_check(not ReplayCodec.encode(malformed_header, Fixture.frames()).ok, "malformed replay header is rejected")
	var wrong_order := Fixture.frames()
	wrong_order[1].tick = 0
	_check(not ReplayCodec.encode(Fixture.header(), wrong_order).ok, "non-monotonic frames are rejected on write")


func _test_mouth_assertions() -> void:
	var state := ReplayCodec.state_from_header(Fixture.header(), Fixture.occupancy_hash())
	var x_frames := Fixture.frames()
	x_frames[0].asserted_mouth_x_fp += 1
	var x_result := ReplaySource.new(x_frames).next_frame(0, state)
	_check(not x_result.ok and "mouth x" in x_result.error, "replay fails immediately on exact x mouth assertion")
	_check(state.player.position_x_fp == Fixture.PLAYER_X_FP, "x assertion failure does not substitute recorded mouth")
	var y_frames := Fixture.frames()
	y_frames[0].asserted_mouth_y_fp -= 1
	var y_result := ReplaySource.new(y_frames).next_frame(0, state)
	_check(not y_result.ok and "mouth y" in y_result.error, "replay fails immediately on exact y mouth assertion")
	_check(state.player.position_y_fp == Fixture.PLAYER_Y_FP, "y assertion failure does not substitute recorded mouth")


func _test_live_replay_equivalence() -> void:
	var header := Fixture.header()
	var state := ReplayCodec.state_from_header(header, Fixture.occupancy_hash())
	var live := LiveSource.new(entries)
	var snapshots := [
		_snapshot(1, 0, false, false, false, Fixture.PLAYER_X_FP + 20 * 256, Fixture.MOUTH_Y_FP),
		_snapshot(-1, 1, true, true, true, Fixture.PLAYER_X_FP, Fixture.MOUTH_Y_FP + 20 * 256),
		_snapshot(0, -1, false, false, true, Fixture.PLAYER_X_FP - 20 * 256, Fixture.MOUTH_Y_FP),
	]
	var live_frames: Array = []
	for snapshot in snapshots:
		live.enqueue_snapshot(snapshot)
	for tick in snapshots.size():
		var result := live.next_frame(tick, state)
		live_frames.append(result.frame)
		if result.frame.move_x != 0:
			state.player.facing = result.frame.move_x
	var encoded := ReplayCodec.encode(header, live_frames)
	var decoded := ReplayCodec.decode(encoded.bytes, header)
	_check(encoded.ok and decoded.ok, "live commands encode into replay source")
	if decoded.ok:
		var replay := ReplaySource.new(decoded.frames)
		state = ReplayCodec.state_from_header(header, Fixture.occupancy_hash())
		var identical := true
		for tick in live_frames.size():
			var result := replay.next_frame(tick, state)
			identical = identical and result.ok and result.frame == live_frames[tick]
			if result.ok and result.frame.move_x != 0:
				state.player.facing = result.frame.move_x
		_check(identical, "live and replay sources produce identical GooCommandFrames")


func _test_runner() -> void:
	var header := Fixture.header()
	var frames := Fixture.frames()
	var runner := Runner.new(ReplayCodec.state_from_header(header, Fixture.occupancy_hash()))
	var result := runner.run_ticks(ReplaySource.new(frames), frames.size())
	_check(result.ok and runner.state.tick == frames.size(), "runner advances ordered explicit tick indexes")
	_check(runner.checkpoint_hashes.size() == frames.size(), "runner records each complete-state checkpoint hash")
	_check(result.hash == Serializer.state_hash(runner.state), "runner final hash uses Package 1A complete-state serializer")
	var bad_frames := Fixture.frames()
	bad_frames[0].tick = 1
	result = Runner.new(ReplayCodec.state_from_header(header, Fixture.occupancy_hash())).run_ticks(ReplaySource.new(bad_frames), 1)
	_check(not result.ok and "tick mismatch" in result.error, "runner rejects mismatched command tick")
	var whole := Runner.new(ReplayCodec.state_from_header(header, Fixture.occupancy_hash()))
	var chunked := Runner.new(ReplayCodec.state_from_header(header, Fixture.occupancy_hash()))
	var whole_source := ReplaySource.new(frames)
	var chunk_source := ReplaySource.new(frames)
	var whole_schedule := whole.schedule_elapsed_microseconds(100000, whole_source)
	var chunks := [13000, 7000, 17000, 9000, 21000, 11000, 22000]
	var scheduled_ticks := 0
	for elapsed in chunks:
		var scheduled := chunked.schedule_elapsed_microseconds(elapsed, chunk_source)
		scheduled_ticks += scheduled.ticks
	_check(whole_schedule.ok and scheduled_ticks == 6 and whole_schedule.ticks == 6, "60 Hz scheduler yields six ticks for 100 ms independent of chunking")
	_check(Serializer.state_hash(whole.state) == Serializer.state_hash(chunked.state), "render/frame scheduling does not alter authoritative state hash")
	_check(whole.checkpoint_hashes == chunked.checkpoint_hashes, "scheduler preserves ordered per-tick hashes")


func _snapshot(move_x: int, move_y: int, jump: bool, spew: bool, gulp: bool, cursor_x: int, cursor_y: int) -> Dictionary:
	return {
		"move_x": move_x,
		"move_y": move_y,
		"jump_pressed": jump,
		"spew_pressed": spew,
		"gulp_pressed": gulp,
		"cursor_x_fp": cursor_x,
		"cursor_y_fp": cursor_y,
	}


func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		printerr("FAIL: %s" % label)
