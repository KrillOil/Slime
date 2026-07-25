extends SceneTree

const ReplayCodec := preload("res://better_spewing/replay/replay_codec.gd")
const ReplaySource := preload("res://better_spewing/replay/replay_command_source.gd")
const Runner := preload("res://better_spewing/runner/authoritative_runner.gd")
const Fixture := preload("res://better_spewing/tests/p1b_fixture_factory.gd")

const EXPECTED_REPLAY_SHA256 := "1803ef9a158645f0d2917e5d3b9eea81c812fcbcf8780d8c91460cf1e9fef1e1"
const EXPECTED_CHECKPOINTS := [
	"cbcf796189da7d2f62a5316eac1848335a9158ff1428eac3366e331650fe1103",
	"d65dc14121a67d31ff5917bb9894a5a48467bc5611c624f4ed3a7aa24f337b4d",
	"f2ce3b0cc3fb7913e53cfd3e228f103f831ed6162e4b35d1811dd0cc29cf4108",
	"66c00c5fd462369da75c4671e5c5aa83ce0f4e0e0f660247b7421cbb43235b3f",
	"2b8da33f0714f16aed5a91f1c3872767ec1654e4df98323c6b04db54daff956f",
	"65d51214e539a4ca91aab40a5a4d983529fd0575f39102d6429675d8ec4c5088",
]
const EXPECTED_FINAL_SHA256 := "65d51214e539a4ca91aab40a5a4d983529fd0575f39102d6429675d8ec4c5088"


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
		printerr("schema-v2 checkpoint fixture mismatch checkpoints=%s final=%s" % [
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
