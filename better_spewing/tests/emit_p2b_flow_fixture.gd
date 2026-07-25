extends SceneTree

const Serializer := preload("res://better_spewing/contracts/canonical_serializer.gd")
const ReplayCodec := preload("res://better_spewing/replay/replay_codec.gd")
const ReplaySource := preload("res://better_spewing/replay/replay_command_source.gd")
const Runner := preload("res://better_spewing/runner/authoritative_runner.gd")
const Fixture := preload("res://better_spewing/tests/p2b_fixture_factory.gd")

const EXPECTED_REPLAY_SHA256 := "97f6780f566d858b6cbaa79dd9513a307ba2f7e923648741b32ac88ded86aa48"
const EXPECTED_CHECKPOINTS: Array[String] = [
	"cfcc6134639dabd54db152585266481d714d88d887c07ec66f56cbe037a0cc6e",
	"e653ea5c9f77a07c6663627ffaf25b919969ab74a0b2c09726f810df37f1ee0a",
	"3c53af5f2a9acba719469f0a2f26e65ebc635f1c50596184fcc6abb9d44e8012",
	"38ae6d3f16d3595a47a8ec8b3a6d4b003fdad36ca54c3fa33d267709341f0c07",
	"f8e9f0a7131f996b8441e5d240a07ac99657567cad1732743c4c8409172d21df",
	"5e50fa70d513b87ddda323702bfa2a7cad6ea2880c494aaefa2a1843009a4fca",
	"2f20773c4c3051323f59b7670412d23f5e0326ad4b3039b95d1e8dc3a85338f0",
	"21805af9c5499f4efdb79e773622b5131b0cdeb8c716a29108fc60c57cd1f7de",
	"3d2fe7b6fd693ca715bf1d5e78fe1a016c57c4ea25e3bfdf8b1db0d815990c1e",
	"d8113d95670e79cc1d5f999ebbfe3adb337c75fd574bf9c034130b74250bdd1a",
	"23c92606e6066639433a670f4e276e6af691977506b49c92959fbcdd9cdc72a3",
	"0b1dc9b5b84625517f4f0f4afc5f2e99dfc503c4f6762d5c8720047091e7c0eb",
	"7c5cf1b82adb1e7abe1ee7157787f84e4abb5660c0422b4b674c5af46f1b33b2",
	"6b57ce8c71447a5e73ab2e5ba8ece4396da45aa625dba805032e8900f3de4ffa",
	"127b8093800b622ee8aa3adabd0d236d3dd67b014f96f13c0745824bbc3e601e",
	"73664cfae8a6867ad57aab9176b54fdbd04e11333a4125991d6c21ec2f5b1cad",
	"43659a86dd3c214a265caebdf913152001e887afb3d14a31bf49731c1d2076ab",
	"a42a6c052774c41d0bd53f64ee9c12e7645c382317533487f29bbdf027a572ce",
	"2a683533b1831340fce41a7d66fc46386daaf530cae28632fa2dd40183190477",
	"b01ffd7ffda841ac19fbd4d11d423db9d57fe09c482835177928739da7036b08",
	"23504e7eac29dcade4ea4f17cad6fa2b30e106ab4ec73b64271a7cebc382c5fe",
	"a2a53e7991e490a7d86388a1a97106ab7743694abf19cd372ddfb2e3030067be",
	"0efe931c3ad3ab88cfc1979904e7dd609cdaf43aa278b0e78e3e2a5b93bdf69b",
	"81c8bf71812f8d5b7023b354d128632db8df1203ebd2d94d6458e9eda2d50222",
	"c14f8cd769e568bdcb61005601c1f42d50cc967138aee60845ccefd8c3e14bdb",
	"049f745bc8b59eab1702120bb873882fb0d0817e0ec8e588bbf4a8c98ccbaf0f",
	"d9d5f8921e5ee69895751e96397d3a61aa3139113fe81633637b21f8da4ff215",
	"0d369b4266733cb28bb29033c235f90d2f2373e4a8ddd80e932466978368509d",
	"2f7a5689d29f3f96e862233cc00cb926d71563e109197d9a2dfa0abd5b1de2cd",
	"e38f2614c9ae31a200a256d898367789e749fee13c10e062f351988b7970d404",
	"97a3f832e101005f777c9b2c59cd44f5a443e3b4a0d54a7feadb12931432da3c",
	"8e22eb0651d6804abecf32a8e225ab5fd4cfb36b26518de61f9548ed498bac61",
]
const EXPECTED_FINAL_SHA256 := "8e22eb0651d6804abecf32a8e225ab5fd4cfb36b26518de61f9548ed498bac61"


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
