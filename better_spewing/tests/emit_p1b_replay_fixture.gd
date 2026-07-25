extends SceneTree

const ReplayCodec := preload("res://better_spewing/replay/replay_codec.gd")
const ReplaySource := preload("res://better_spewing/replay/replay_command_source.gd")
const Runner := preload("res://better_spewing/runner/authoritative_runner.gd")
const Fixture := preload("res://better_spewing/tests/p1b_fixture_factory.gd")

const EXPECTED_REPLAY_SHA256 := "1803ef9a158645f0d2917e5d3b9eea81c812fcbcf8780d8c91460cf1e9fef1e1"
const EXPECTED_CHECKPOINTS := [
	"7a01f7badb7135c7bdc445bc97aea517aae7554216f76380faa94d72abb04bcf",
	"d233f0e2c81840a9490ef1736f4b49a018339d42a79e8be6131ee942362a082a",
	"c95fb71462a11d9dd4e76dd25dcf6af54a033d7116691ca63bb537efe07bdd07",
	"c1d0de4f8c877265fbc6b24ded84b2a8aca09f2bbb730ec0fb4e25d0159a424e",
	"cea489cb8c009672f0bb060ca411c627eb0bc3a62cb737fae2cd851cd27d5fff",
	"ef8617121a6f8e36ef45960876b85a5a5397010b2478ab5ba04e0614b9bcfaa5",
]
const EXPECTED_FINAL_SHA256 := "ef8617121a6f8e36ef45960876b85a5a5397010b2478ab5ba04e0614b9bcfaa5"


func _init() -> void:
	var bytes := Fixture.replay_bytes()
	var decoded := ReplayCodec.decode(bytes, Fixture.header())
	if not decoded.ok:
		printerr(decoded.error)
		quit(1)
		return
	var state := ReplayCodec.state_from_header(decoded.header, Fixture.occupancy_hash())
	var runner := Runner.new(state)
	var result := runner.run_ticks(ReplaySource.new(decoded.frames), decoded.frames.size())
	if not result.ok:
		printerr(result.error)
		quit(1)
		return
	var replay_hash := _sha256(bytes)
	if replay_hash != EXPECTED_REPLAY_SHA256:
		printerr("replay byte fixture mismatch")
		quit(1)
		return
	if runner.checkpoint_hashes != EXPECTED_CHECKPOINTS or result.hash != EXPECTED_FINAL_SHA256:
		printerr("schema-v3 checkpoint fixture mismatch checkpoints=%s final=%s" % [
			",".join(PackedStringArray(runner.checkpoint_hashes)),
			result.hash,
		])
		quit(1)
		return
	print("P1B_REPLAY bytes=%d replay_sha256=%s checkpoints=%s final=%s" % [
		bytes.size(),
		replay_hash,
		",".join(PackedStringArray(runner.checkpoint_hashes)),
		result.hash,
	])
	quit(0)


func _sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()
