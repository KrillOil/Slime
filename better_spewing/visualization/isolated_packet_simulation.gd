extends Node2D

const Contracts := preload("res://better_spewing/contracts/goo_contracts.gd")
const Schema := preload("res://better_spewing/contracts/canonical_state_schema.gd")
const Serializer := preload("res://better_spewing/contracts/canonical_serializer.gd")
const MouthDerivation := preload("res://better_spewing/runner/mouth_derivation.gd")
const Runner := preload("res://better_spewing/runner/authoritative_runner.gd")
const RoomOccupancy := preload("res://better_spewing/collision/room_occupancy.gd")

var runner: RefCounted
var authoritative_snapshots: Array = []
var authoritative_hash_before_render := ""


func _ready() -> void:
	var state := Schema.default_state()
	state.ledger.initial = 1600
	state.ledger.reserve = 1600
	state.player.position_x_fp = 120 * 256
	state.player.position_y_fp = 180 * 256
	var room := RoomOccupancy.build({
		"identifier": "package-1d-visualization",
		"solids": [Rect2(200.0, 0.0, 10.0, 540.0)],
	})
	runner = Runner.new(state, room)
	for action in [
		Contracts.GooAction.SPEW,
		Contracts.GooAction.NONE,
		Contracts.GooAction.NONE,
		Contracts.GooAction.NONE,
		Contracts.GooAction.NONE,
		Contracts.GooAction.NONE,
		Contracts.GooAction.NONE,
	]:
		var mouth := MouthDerivation.derive(runner.state.player)
		var result: Dictionary = runner.step_frame({
			"tick": runner.state.tick,
			"move_x": 0,
			"move_y": 0,
			"jump_pressed": false,
			"goo_action": action,
			"aim_angle": 0,
			"asserted_mouth_x_fp": mouth.x,
			"asserted_mouth_y_fp": mouth.y,
		})
		if not result.ok:
			push_error("isolated authoritative packet sequence failed: %s" % result.error)
			return
		authoritative_snapshots.append(runner.state.packets.duplicate(true))
	authoritative_hash_before_render = Serializer.state_hash(runner.state)
	$PacketVisualizer.set_packet_snapshot(runner.state.packets)
