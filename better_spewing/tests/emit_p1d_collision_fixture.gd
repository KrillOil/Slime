extends SceneTree

const ReplayCodec := preload("res://better_spewing/replay/replay_codec.gd")
const ReplaySource := preload("res://better_spewing/replay/replay_command_source.gd")
const Runner := preload("res://better_spewing/runner/authoritative_runner.gd")
const Fixture := preload("res://better_spewing/tests/p1d_fixture_factory.gd")
const Contracts := preload("res://better_spewing/contracts/goo_contracts.gd")

const EXPECTED_REPLAY_SHA256 := "df983d0b9706cd6e7beeaf7b3f7f9d9d236b600bda9e65403b12bb50198c4288"
const EXPECTED_CHECKPOINTS: Array[String] = [
	"b30443a992dd61a498b2ca085e33ee4c92e0acadf3f04f576ec94302c6e84974",
	"7120c95d383fe687c1d2754a8296cce878788ef3c55889786b432caa0a1e5ada",
	"0ecf92a43b35b9bdb49b6f6f2f53e871789ed86acc17784ee38f383fce0205be",
	"62b52bcbb6f3b7f02edff2d3b8f5a3f160f644a21f1f07ed27a17a71e191127c",
	"984afdc23038ba2f383ec52d037217ee739f24a8383b9dc95a75f9583df09688",
	"bea631557751d5c30778934d6a36c0bde109f339b7019a62de63ffe331588e60",
]
const EXPECTED_FINAL_SHA256 := "bea631557751d5c30778934d6a36c0bde109f339b7019a62de63ffe331588e60"


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
		printerr("Package 1D replay byte round-trip mismatch")
		quit(1)
		return
	var state := ReplayCodec.state_from_header(decoded.header, room.occupancy_hash)
	var runner := Runner.new(state, room)
	var result := runner.run_ticks(ReplaySource.new(decoded.frames), decoded.frames.size())
	if not result.ok:
		printerr(result.error)
		quit(1)
		return
	var replay_hash := _sha256(bytes)
	print("P1D_REPLAY bytes=%d replay_sha256=%s checkpoints=%s final=%s stationary=%d settled_q=%d drain_q=%d" % [
		bytes.size(), replay_hash, ",".join(PackedStringArray(runner.checkpoint_hashes)), result.hash,
		_stationary_count(runner.state.packets), runner.state.ledger.settled, runner.state.ledger.drain,
	])
	if not EXPECTED_REPLAY_SHA256.is_empty() and replay_hash != EXPECTED_REPLAY_SHA256:
		printerr("Package 1D replay byte fixture mismatch")
		quit(1)
		return
	if not EXPECTED_CHECKPOINTS.is_empty() and (
		runner.checkpoint_hashes != EXPECTED_CHECKPOINTS or result.hash != EXPECTED_FINAL_SHA256
	):
		printerr("Package 1D complete-state checkpoint fixture mismatch")
		quit(1)
		return
	if _stationary_count(runner.state.packets) != 0 or runner.state.ledger.settled <= 0 or runner.state.ledger.drain <= 0:
		printerr("Package 1D replay did not exercise both collision deposition and bounds drain")
		quit(1)
		return
	quit(0)


func _stationary_count(packets: Array) -> int:
	var total := 0
	for packet in packets:
		if packet.lifecycle == Contracts.PacketLifecycle.STATIONARY_DEPOSITION:
			total += 1
	return total


func _sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()
