extends Node2D

const VIEW_SIZE := Vector2(960, 540)
const LEVEL_SCENES := [
	"res://scenes/game.tscn",
	"res://scenes/level_2.tscn",
	"res://scenes/level_3.tscn",
	"res://scenes/level_4.tscn",
]

@export_range(1, 4) var room_index := 1

@onready var player: GulpPlayer = $Player
@onready var goo_meter: ProgressBar = $HUD/GooMeter
@onready var room_label: Label = $HUD/RoomLabel
@onready var instruction_label: Label = $HUD/InstructionLabel
@onready var message_label: Label = $HUD/Message

var solid_rects: Array[Rect2] = []
var spike_rects: Array[Rect2] = []
var door_rect := Rect2()
var transitioning := false


func _ready() -> void:
	_build_room()
	goo_meter.value = player.goo_reserve
	player.reserve_changed.connect(_on_reserve_changed)
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart"):
		restart_level()


func _draw() -> void:
	draw_rect(Rect2(0, 0, VIEW_SIZE.x, VIEW_SIZE.y), Color("#09111f"))
	for rect in solid_rects:
		draw_rect(rect, Color("#32455b"))
		draw_line(rect.position, Vector2(rect.end.x, rect.position.y), Color("#66809a"), 3.0)
	for spike_rect in spike_rects:
		var spike_width := 22.0
		var count := maxi(1, floori(spike_rect.size.x / spike_width))
		for index in count:
			var left := spike_rect.position.x + index * spike_rect.size.x / count
			var right := spike_rect.position.x + (index + 1) * spike_rect.size.x / count
			draw_colored_polygon(PackedVector2Array([
				Vector2(left, spike_rect.end.y),
				Vector2((left + right) * 0.5, spike_rect.position.y),
				Vector2(right, spike_rect.end.y),
			]), Color("#ff5370"))
	if door_rect.size != Vector2.ZERO:
		draw_rect(door_rect, Color("#f9c74f"))
		draw_rect(door_rect.grow(-6.0), Color("#18233a"))
		draw_circle(door_rect.position + Vector2(door_rect.size.x - 11.0, door_rect.size.y * 0.55), 3.0, Color("#f9c74f"))


func _on_reserve_changed(value: float) -> void:
	goo_meter.value = value


func _physics_process(_delta: float) -> void:
	if player.global_position.y > 620.0 and not transitioning:
		restart_level()


func restart_level() -> void:
	if transitioning:
		return
	get_tree().reload_current_scene()


func _build_room() -> void:
	var definition := _room_definition(room_index)
	solid_rects.assign(definition.solids)
	spike_rects.assign(definition.spikes)
	door_rect = definition.door
	player.global_position = definition.spawn
	player.set_goo_reserve(definition.initial_goo)
	room_label.text = "ROOM %d/4  —  %s" % [room_index, definition.name]
	instruction_label.text = definition.instruction
	for rect in solid_rects:
		_add_solid(rect)
	for rect in spike_rects:
		_add_trigger(rect, Callable(self, "_on_spike_body_entered"))
	_add_trigger(door_rect, Callable(self, "_on_goal_body_entered"))


func _add_solid(rect: Rect2) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 2
	body.position = rect.get_center()
	var shape_node := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	shape_node.shape = shape
	body.add_child(shape_node)
	$Geometry.add_child(body)


func _add_trigger(rect: Rect2, callback: Callable) -> void:
	var area := Area2D.new()
	area.collision_layer = 4
	area.collision_mask = 2
	area.position = rect.get_center()
	var shape_node := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	shape_node.shape = shape
	area.add_child(shape_node)
	area.body_entered.connect(callback)
	$Triggers.add_child(area)


func _on_spike_body_entered(body: Node2D) -> void:
	if body == player:
		restart_level()


func _on_goal_body_entered(body: Node2D) -> void:
	if body != player or transitioning:
		return
	transitioning = true
	player.controls_enabled = false
	if room_index >= 4:
		message_label.text = "YOU WIN!\nThanks for playing GULP"
		message_label.visible = true
		instruction_label.text = "Press R to play this room again"
		transitioning = false
		return
	message_label.text = "ROOM CLEAR!"
	message_label.visible = true
	await get_tree().create_timer(0.45).timeout
	get_tree().change_scene_to_file(LEVEL_SCENES[room_index])


func _room_definition(index: int) -> Dictionary:
	match index:
		1:
			return {
				"name": "BASICS",
				"instruction": "A/D move  •  SPACE jump  •  R restart",
				"spawn": Vector2(82, 446),
				"initial_goo": 100.0,
				"solids": [
					Rect2(0, 480, 430, 60),
					Rect2(535, 480, 425, 60),
					Rect2(430, 525, 105, 15),
				],
				"spikes": [],
				"door": Rect2(872, 406, 48, 74),
			}
		2:
			return {
				"name": "FILL",
				"instruction": "Hold LMB to spew toward the cursor  •  Swim with WASD/SPACE",
				"spawn": Vector2(85, 346),
				"initial_goo": 100.0,
				"solids": [
					Rect2(0, 380, 245, 160),
					Rect2(705, 380, 255, 160),
				],
				"spikes": [Rect2(245, 510, 460, 30)],
				"door": Rect2(865, 306, 48, 74),
			}
		3:
			return {
				"name": "BOOST",
				"instruction": "Spew DOWN while grounded, then SPACE for a boosted jump",
				"spawn": Vector2(95, 446),
				"initial_goo": 100.0,
				"solids": [
					Rect2(0, 480, 600, 60),
					Rect2(600, 300, 360, 240),
				],
				"spikes": [],
				"door": Rect2(845, 226, 48, 74),
			}
		_:
			return {
				"name": "COMBO",
				"instruction": "Swim across  •  Hold RMB/SHIFT nearby to gulp  •  Boost to the door",
				"spawn": Vector2(80, 386),
				"initial_goo": 68.0,
				"solids": [
					Rect2(0, 420, 190, 120),
					Rect2(650, 420, 110, 120),
					Rect2(760, 250, 200, 290),
				],
				"spikes": [Rect2(190, 510, 460, 30)],
				"door": Rect2(860, 176, 48, 74),
			}
