extends SceneTree

const ReplayCodec := preload("res://better_spewing/replay/replay_codec.gd")
const ReplaySource := preload("res://better_spewing/replay/replay_command_source.gd")
const Runner := preload("res://better_spewing/runner/authoritative_runner.gd")
const Fixture := preload("res://better_spewing/tests/p2a_fixture_factory.gd")

const EXPECTED_REPLAY_SHA256 := "b6d07e62c4de520d7be19bb4a5c627bcb5687a67b7ef251c8130263c68e6d746"
const EXPECTED_CHECKPOINTS: Array[String] = [
	"15ae9f664b69de0615a81754c5130297750ac1b8086434cd4bdb2263972e95db",
	"1e4ee502857d08b797112440f3a6b8fe70f46f468a270f345df52b13bfd1b4ae",
	"a6dbd003972cb93cb711cba9b2835d70a5ba9160dfd962a4d8434c864bc5440c",
	"1de00f46b43a4e6268ed4c67b20abb529ab33173db676941cc6a31be92e061ca",
	"e95671f127fc1f6ad10617d34b3992f1afe1e60d1642175ff04d496e7ba0ae69",
	"2b6c1787627eeba9471016be4fff320b1515de29e302d8b51856467c593317b5",
	"e44fa05320c15e02cfeb52b1b5530a0f5d41f571b7e5ebbe0ba873c0fe4f1acc",
	"02c6e7eb28b7feebc7f136f5434ab714b72cc7ca2f60912101fff9f9037b0d71",
]
const EXPECTED_FINAL_SHA256 := "02c6e7eb28b7feebc7f136f5434ab714b72cc7ca2f60912101fff9f9037b0d71"


func _init() -> void:
	var room := Fixture.room_context()
	var bytes := Fixture.replay_bytes()
	var decoded := ReplayCodec.decode(bytes, Fixture.header())
	if not decoded.ok:
		printerr(decoded.error)
		quit(1)
		return
	var reencoded := ReplayCodec.encode(decoded.header, decoded.frames)
	if not reencoded.ok or reencoded.bytes != bytes:
		printerr("Package 2A replay byte round-trip mismatch")
		quit(1)
		return
	var state := ReplayCodec.state_from_header(decoded.header, room.occupancy_hash)
	var runner := Runner.new(state, room)
	var source := ReplaySource.new(decoded.frames)
	var flow_ok := false
	for unused in decoded.frames.size():
		var result := runner.step_from_source(source)
		if not result.ok:
			printerr(result.error)
			quit(1)
			return
		flow_ok = flow_ok or not runner.state.active_queue.is_empty()
	var replay_hash := _sha256(bytes)
	var final_hash := runner.checkpoint_hashes[-1]
	print("P2A_REPLAY bytes=%d replay_sha256=%s checkpoints=%s final=%s settled_q=%d nonzero_cells=%d partial_retry=%s" % [
		bytes.size(), replay_hash, ",".join(PackedStringArray(runner.checkpoint_hashes)),
		final_hash, runner.state.ledger.settled, _nonzero_cells(runner.state.settled_cells),
		flow_ok,
	])
	if not EXPECTED_REPLAY_SHA256.is_empty() and replay_hash != EXPECTED_REPLAY_SHA256:
		printerr("Package 2A replay byte fixture mismatch")
		quit(1)
		return
	if not EXPECTED_CHECKPOINTS.is_empty() and (
		runner.checkpoint_hashes != EXPECTED_CHECKPOINTS or final_hash != EXPECTED_FINAL_SHA256
	):
		printerr("Package 2A checkpoint fixture mismatch")
		quit(1)
		return
	if not flow_ok or not runner.state.packets.is_empty() \
			or runner.state.ledger.settled != 21 or _nonzero_cells(runner.state.settled_cells) != 4:
		printerr("Package 2A replay did not reconcile conserved deposition into active flow")
		quit(1)
		return
	quit(0)


func _nonzero_cells(cells: Array) -> int:
	var total := 0
	for volume in cells:
		if volume > 0:
			total += 1
	return total


func _sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()
