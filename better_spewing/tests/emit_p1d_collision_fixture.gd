extends SceneTree

const ReplayCodec := preload("res://better_spewing/replay/replay_codec.gd")
const ReplaySource := preload("res://better_spewing/replay/replay_command_source.gd")
const Runner := preload("res://better_spewing/runner/authoritative_runner.gd")
const Fixture := preload("res://better_spewing/tests/p1d_fixture_factory.gd")
const Contracts := preload("res://better_spewing/contracts/goo_contracts.gd")

const EXPECTED_REPLAY_SHA256 := "df983d0b9706cd6e7beeaf7b3f7f9d9d236b600bda9e65403b12bb50198c4288"
const EXPECTED_CHECKPOINTS: Array[String] = [
	"9ba8b04c1caf175b9d0e254be58226b337b9ce4f88c82a525efd453e3077f508",
	"7897b7cecda980f12ad6155a01d97313676515e40606f543f34806bda79bd3bd",
	"599cc70e22d77468411d8e7f5adbeb812c2aa51944a4409230a04eff1da09ba4",
	"68fc15374e029249a17af34346b6bf5756e0695a9fb7a402f549ea6a657b4373",
	"bc480ec41fe9a0fe3b0fea3eaac1901dbfcd4fda66bbafa22ef29ec6711a8cdb",
	"5d5fcfcab2c8ca394a8b5f36f8a8028248305232de9f23324c65a23670c13294",
]
const EXPECTED_FINAL_SHA256 := "5d5fcfcab2c8ca394a8b5f36f8a8028248305232de9f23324c65a23670c13294"


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
	print("P1D_REPLAY bytes=%d replay_sha256=%s checkpoints=%s final=%s stationary=%d drain_q=%d" % [
		bytes.size(), replay_hash, ",".join(PackedStringArray(runner.checkpoint_hashes)), result.hash,
		_stationary_count(runner.state.packets), runner.state.ledger.drain,
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
	if _stationary_count(runner.state.packets) != 1 or runner.state.ledger.drain <= 0:
		printerr("Package 1D replay did not exercise both collision and bounds drain")
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
