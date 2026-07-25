extends SceneTree

const ReplayCodec := preload("res://better_spewing/replay/replay_codec.gd")
const ReplaySource := preload("res://better_spewing/replay/replay_command_source.gd")
const Runner := preload("res://better_spewing/runner/authoritative_runner.gd")
const Fixture := preload("res://better_spewing/tests/p1b_fixture_factory.gd")

const EXPECTED_REPLAY_SHA256 := "9fb7dd092fa8ad75a49e6a2ba1590a91b96d33812db982a71201af3d1644a0b4"
const EXPECTED_CHECKPOINTS := [
	"3c5f08648f9c56371dc0d6a8a875a6f7c4164547c480b77581308ead150dd03d",
	"3504a35328a1d03464de10a16b89bf6610948858311f789a2f0c4e184c537de7",
	"ff3034af6b6399bc5cf909d4a015aa2eef3594c74412afa59afacb94c529f8be",
	"81293372635124fc99745af92417dc09892f6ca5e968cf92d7496e4f86aa7338",
	"b65ba9783132dc9f9caa606f4409b905886b1e41ee4465edc2d15bb0a9b30e5b",
	"439ba49b1aafe29911d98bfe6bf96bd77d9b2d32ff975e9577b69939c1a6d5ee",
]
const EXPECTED_FINAL_SHA256 := "439ba49b1aafe29911d98bfe6bf96bd77d9b2d32ff975e9577b69939c1a6d5ee"


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
