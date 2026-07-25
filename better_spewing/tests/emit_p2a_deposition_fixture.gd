extends SceneTree

const ReplayCodec := preload("res://better_spewing/replay/replay_codec.gd")
const ReplaySource := preload("res://better_spewing/replay/replay_command_source.gd")
const Runner := preload("res://better_spewing/runner/authoritative_runner.gd")
const Fixture := preload("res://better_spewing/tests/p2a_fixture_factory.gd")

const EXPECTED_REPLAY_SHA256 := "bd731435f464ef66c46f1fc01d5fd1f0ed4dc1fb516e37f04438b0f6426a14ae"
const EXPECTED_CHECKPOINTS: Array[String] = [
	"e8aa0c3d7b1bf25764beb04e6924c68cc077d4b720b1b4a5973b8df0fb9c2159",
	"e40c868e79284f8cab090fac9e93cbe3b6c933d12cfc9fcc16c1f0df603c823c",
	"a3bba464460b3a6314f4689866116397fb6951d6147c7b88efa3da01d157e7f2",
	"bb98ce4b8eca4a77737e2867a6908d799ccf319f54279d94b1ccaaee5baa7aa5",
	"bf3e53ad25844b93b763900069f6f3f6bf50bc57bdeddc4b4842a554941d5965",
	"d6269cf7e20443ab23d1c927bc40d041f90778ec9cde533e6cdf582a887ca8cd",
	"e9df80c200082dbd42156b799339168ad55238409591bf821f571cedc274c6b3",
	"144db0570d55689d6124d1702e5d58c69e8ca83fabd69a286f8e9ef57ba97bb2",
]
const EXPECTED_FINAL_SHA256 := "144db0570d55689d6124d1702e5d58c69e8ca83fabd69a286f8e9ef57ba97bb2"


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
