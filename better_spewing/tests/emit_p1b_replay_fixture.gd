extends SceneTree

const ReplayCodec := preload("res://better_spewing/replay/replay_codec.gd")
const ReplaySource := preload("res://better_spewing/replay/replay_command_source.gd")
const Runner := preload("res://better_spewing/runner/authoritative_runner.gd")
const Fixture := preload("res://better_spewing/tests/p1b_fixture_factory.gd")


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
	print("P1B_REPLAY bytes=%d replay_sha256=%s checkpoints=%s final=%s" % [
		bytes.size(),
		_sha256(bytes),
		",".join(PackedStringArray(runner.checkpoint_hashes)),
		result.hash,
	])
	quit(0)


func _sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()
