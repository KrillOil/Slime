extends SceneTree

const Serializer := preload("res://better_spewing/contracts/canonical_serializer.gd")
const ReplayCodec := preload("res://better_spewing/replay/replay_codec.gd")
const ReplaySource := preload("res://better_spewing/replay/replay_command_source.gd")
const Runner := preload("res://better_spewing/runner/authoritative_runner.gd")
const Fixture := preload("res://better_spewing/tests/p2b_fixture_factory.gd")

const EXPECTED_REPLAY_SHA256 := "7d697128895f721c67de5ffecb340497af3210bd0a9624b0cca35fac8c90c558"
const EXPECTED_CHECKPOINTS: Array[String] = [
	"55262c2b5c3d31fc47b46281f0bc8201dae80828febe0483c6269f4715d9870d",
	"5de14d43199a2dfae003523c66c773a680f64069f92d592e37d1e15b4b54cd91",
	"0fcb798842b0a49a2cad6104c681be419f0aeeee1115315001a24d0be087f980",
	"b618547b1a5e6ac2fd119de21c743249f338d648c9394e9d88d3a32635ff7ddf",
	"34948efd76ea7ebb48294329c03f5ee8804d7597f35ab342db1c5652b6683a5c",
	"d2ff67a27a38a64c8e805e413f2cb719a713345954092a3386578eb3e5d2be6d",
	"8ba10e3b2bade940e40f704ec571a523f5593f11ff0ce1c38faabf7aeb4b1571",
	"e1693d1ce3f431dbf541e1a7e5136e8fd33749034265805ad5adb806f8cce9fa",
	"6ac894118c359e9a6515d7c68c4e604d2dba50e04e61453b7a3d9080564796a3",
	"f79c38465454464649eeb291584bea4a05a6fef5a8f2bbcb82120fc187ceb087",
	"c70920848f2d80fa79a115d14ced21092fe5e2fe62062c03c6eb34700a569abd",
	"e8b96139f6a131987c12f43efce38d90836839c374cf8bc3d3f234ef59140c97",
	"04d6dff38743ffb216e933f802f624e86e9504083930a9ec62eee6802d6ce49a",
	"a4595f73f687d95477d0fcb37853ebe64982da5f4b2d8de0fd62b558c22263bb",
	"efae81e11efe0df8f70cd249e1520367b7b86368f003170d2d2624068e650cf7",
	"85e0160e77619562902870da91b71b76f53013ac02fb8d0b32ab15654056dbb4",
	"cbc81e828538df905b17f2f705a5dd3594f45cefb366fc179e31a8d725ca5fc0",
	"5a15099198289950d62dd567e819f11cfea9c2e7d69b007fe37aea0050138cb5",
	"78a3f51638e890d36f157b745657e17c167b92e5a6dd4065253037df27de4462",
	"0edc520b1c2c72c1b6e4e752514ec5711f430e7d9b9e663d9d0048da0a6234d5",
	"39979e1e74e0c7b4d7e58d5641989c0b99dc8971cc617b1a07c1a3dee8b25b82",
	"14e2d179e866f930144b008038dc52c8db997b1ff338d4d331fe62f528ab63f3",
	"4dae3caafba0f3a4a88c3517e765a94d14bfb73222171ca0a7d0e8b10d80d12f",
	"8a31a16e3c37c6819374f373e6a5d539494e5b3bffe8b0e257f3fe75c32e673e",
	"ec09ef47c576d61c7250c4957c72a0b3b3877e5b98d6f665905845534ae46eac",
	"1dae95c4c133b872f6abd43779bb931fa4731b8acb02337b7f548905cd7e8990",
	"b708678430257e338016144cdc352c6a36a9c1b20df2757e82911355e24aeedc",
	"9460197e014379b847259e98cbff6dbf32ac829abe3afd8512682d7ad2c56a06",
	"60be1204cc8aa84c8647dac2983d5a172a6c3f4cfba7c9a8e1cbe4f47b708a2f",
	"e5a10c470b25f9a2cf23055b2d5b2d2200e9443ba184ef4bd0b70194a3bf42db",
	"de7880d1dcfaa5a80d3de95b13e43c7ed5a45371276f6de468bc02cc4a2fbfd2",
	"cf36af175f9e1971dc8f119612692cd4e552cfb94ebb153099fefecc63ba36fc",
]
const EXPECTED_FINAL_SHA256 := "cf36af175f9e1971dc8f119612692cd4e552cfb94ebb153099fefecc63ba36fc"


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
		printerr("Package 2B replay byte round-trip mismatch")
		quit(1)
		return
	var state := ReplayCodec.state_from_header(decoded.header, room.occupancy_hash)
	var runner := Runner.new(state, room)
	Fixture.seed_state(runner.state, room)
	var source := ReplaySource.new(decoded.frames)
	var invariant_ok := true
	for unused in decoded.frames.size():
		var result := runner.step_from_source(source)
		invariant_ok = invariant_ok and result.ok \
			and _sum(runner.state.settled_cells) == runner.state.ledger.settled \
			and _ledger_error(runner.state) == 0
	var replay_hash := _sha256(bytes)
	var final_hash := runner.checkpoint_hashes[-1]
	print("P2B_REPLAY bytes=%d replay_sha256=%s checkpoints=%s final=%s settled_q=%d active=%d invariant=%s" % [
		bytes.size(), replay_hash,
		",".join(PackedStringArray(runner.checkpoint_hashes)),
		final_hash, runner.state.ledger.settled,
		runner.state.active_queue.size(), invariant_ok,
	])
	if not EXPECTED_REPLAY_SHA256.is_empty() and replay_hash != EXPECTED_REPLAY_SHA256:
		printerr("Package 2B replay byte fixture mismatch")
		quit(1)
		return
	if not EXPECTED_CHECKPOINTS.is_empty() and (
		runner.checkpoint_hashes != EXPECTED_CHECKPOINTS
		or final_hash != EXPECTED_FINAL_SHA256
	):
		printerr("Package 2B checkpoint fixture mismatch")
		quit(1)
		return
	if not invariant_ok or runner.state.ledger.settled != 48:
		printerr("Package 2B replay violated conservation")
		quit(1)
		return
	quit(0)


func _sum(values: Array) -> int:
	var total := 0
	for value in values:
		total += value
	return total


func _ledger_error(state: Dictionary) -> int:
	return state.ledger.initial - (
		state.ledger.reserve + state.ledger.airborne + state.ledger.settled
		+ state.ledger.suction + state.ledger.recovery_queue + state.ledger.drain
	)


func _sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()
