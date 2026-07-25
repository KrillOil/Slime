extends SceneTree

const ReplayCodec := preload("res://better_spewing/replay/replay_codec.gd")
const ReplaySource := preload("res://better_spewing/replay/replay_command_source.gd")
const Runner := preload("res://better_spewing/runner/authoritative_runner.gd")
const Fixture := preload("res://better_spewing/tests/p2a_fixture_factory.gd")

const EXPECTED_REPLAY_SHA256 := "bd731435f464ef66c46f1fc01d5fd1f0ed4dc1fb516e37f04438b0f6426a14ae"
const EXPECTED_CHECKPOINTS: Array[String] = [
	"e8aa0c3d7b1bf25764beb04e6924c68cc077d4b720b1b4a5973b8df0fb9c2159",
	"e40c868e79284f8cab090fac9e93cbe3b6c933d12cfc9fcc16c1f0df603c823c",
	"363aabbda9e8f0ec1936351d913c4f8990440741e59874120eec774f44a0fd33",
	"93755b687ea2a86591db64f857dcdd7ed3a1537a0c6f20ef2703cb9a6129ea55",
	"e9cf256d3cf229c2d7bf7cd5d47c63d9f94a45841e0b91f288d45e5b28e6626e",
	"5825e32d4bc13195214258b39f87cae39fe5c3b43f2e6132e73c83a8d21fde86",
	"ac1e332c79d1e482245f37a29ada1a11025df8d5b05ae1f3f50c1659b122ffe6",
	"a26c83e7efa16fe83b51144fd16ff2b7cd7e028ae414cadf07c9d9960e5ffeed",
]
const EXPECTED_FINAL_SHA256 := "a26c83e7efa16fe83b51144fd16ff2b7cd7e028ae414cadf07c9d9960e5ffeed"


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
	var partial_ok := false
	for unused in decoded.frames.size():
		var result := runner.step_from_source(source)
		if not result.ok:
			printerr(result.error)
			quit(1)
			return
		if runner.state.tick == 7:
			partial_ok = (
				runner.state.packets.size() == 1
				and runner.state.packets[0].id == 3
				and runner.state.packets[0].volume_q == 5
				and runner.state.packets[0].lifecycle == 1
			)
	var replay_hash := _sha256(bytes)
	var final_hash := runner.checkpoint_hashes[-1]
	print("P2A_REPLAY bytes=%d replay_sha256=%s checkpoints=%s final=%s settled_q=%d nonzero_cells=%d partial_retry=%s" % [
		bytes.size(), replay_hash, ",".join(PackedStringArray(runner.checkpoint_hashes)),
		final_hash, runner.state.ledger.settled, _nonzero_cells(runner.state.settled_cells),
		partial_ok,
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
	if not partial_ok or not runner.state.packets.is_empty() \
			or runner.state.ledger.settled != 21 or _nonzero_cells(runner.state.settled_cells) != 2:
		printerr("Package 2A replay did not exercise deterministic saturation retry")
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
