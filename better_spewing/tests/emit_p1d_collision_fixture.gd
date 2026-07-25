extends SceneTree

const ReplayCodec := preload("res://better_spewing/replay/replay_codec.gd")
const ReplaySource := preload("res://better_spewing/replay/replay_command_source.gd")
const Runner := preload("res://better_spewing/runner/authoritative_runner.gd")
const Fixture := preload("res://better_spewing/tests/p1d_fixture_factory.gd")
const Contracts := preload("res://better_spewing/contracts/goo_contracts.gd")

const EXPECTED_REPLAY_SHA256 := "2a72c87ae8dc03a99c67bcd5c07d9bfa8615d0cfff5980f790fd3eca64ae04fa"
const EXPECTED_CHECKPOINTS: Array[String] = [
	"ce1ebaa8d6c40744485a3946fb18820fc452e6cd2eef8cb1cdf0d2bfd9303655",
	"b0ee7285733f68b50f27e0fa736bb154576eda4b0755affdca202eb4d3285209",
	"dac59461c30e37f1ed38ec734372eda4180e652cea0ef14df0cfdf4d23ff4a9b",
	"fdcce52f7eef060c871e7035c527f658d4a4abf43ce88b10c4322424d7c997ae",
	"19b6214c83a86d4cd1c673f53e263e96c52c891a5737d75296a15d06746d5d43",
	"7bc8156fb2052e20502be768cc882c98b82c790c38551ec0296bafc92bddb769",
]
const EXPECTED_FINAL_SHA256 := "7bc8156fb2052e20502be768cc882c98b82c790c38551ec0296bafc92bddb769"


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
