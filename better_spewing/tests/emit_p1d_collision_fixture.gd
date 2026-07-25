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
	"fde694df7812ada71f9c80054775cc4b20e05225e87ad2045620f9e428849649",
	"732b8ffa9e895b7fc46756f1497b6eb728da394dc6bdaae0e1756fe5d9ba477d",
	"436aa607fa6f5034b18fcd3885eec09b77560d36cc0817a21d834f260dbe273a",
	"902ccf3a0d9b2ba5fab8a6d8ca1b05d71e37dbc61e7493e562771bb0fd525e0e",
]
const EXPECTED_FINAL_SHA256 := "902ccf3a0d9b2ba5fab8a6d8ca1b05d71e37dbc61e7493e562771bb0fd525e0e"


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
