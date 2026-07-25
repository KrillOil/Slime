class_name GulpPlayer
extends CharacterBody2D

signal reserve_changed(value: float)

const WALK_SPEED := 245.0
const GROUND_ACCELERATION := 1800.0
const AIR_ACCELERATION := 1050.0
const FRICTION := 2200.0
const GRAVITY := 1500.0
const JUMP_SPEED := 510.0
const BOOST_JUMP_SPEED := 770.0
const SWIM_SPEED := 205.0
const SWIM_ACCELERATION := 720.0
const MAX_GOO := 100.0
const SPEW_RATE := 28.0
const GULP_RATE := 42.0
const SWIM_WETNESS_THRESHOLD := 0.08
const BOOST_CHARGE_REQUIRED := 7.0

var controls_enabled := true
var goo_reserve := MAX_GOO
var goo_grid: Node2D
var is_swimming := false
var recent_down_spew_time := 0.0
var down_spew_charge := 0.0


func _ready() -> void:
	goo_grid = get_tree().get_first_node_in_group("goo_grid") as Node2D
	reserve_changed.emit(goo_reserve)
	queue_redraw()


func _physics_process(delta: float) -> void:
	if not controls_enabled:
		velocity = Vector2.ZERO
		return

	recent_down_spew_time = maxf(recent_down_spew_time - delta, 0.0)
	if recent_down_spew_time <= 0.0:
		down_spew_charge = 0.0
	_update_swimming_state()
	if is_swimming:
		_process_swimming(delta)
		_process_goo(delta)
		move_and_slide()
		return

	var direction := Input.get_axis("move_left", "move_right")
	var acceleration := GROUND_ACCELERATION if is_on_floor() else AIR_ACCELERATION
	if not is_zero_approx(direction):
		velocity.x = move_toward(velocity.x, direction * WALK_SPEED, acceleration * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)

	if not is_on_floor():
		velocity.y += GRAVITY * delta
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = -take_jump_speed()

	_process_goo(delta)
	move_and_slide()


func _process_swimming(delta: float) -> void:
	var swim_input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if Input.is_action_pressed("jump"):
		swim_input.y = -1.0
	if swim_input == Vector2.ZERO:
		swim_input = Vector2(0.0, -0.18)
	velocity = velocity.move_toward(swim_input.normalized() * SWIM_SPEED, SWIM_ACCELERATION * delta)


func _update_swimming_state() -> void:
	var was_swimming := is_swimming
	is_swimming = goo_grid != null and goo_grid.sample_wetness(global_position, 38.0) >= SWIM_WETNESS_THRESHOLD
	if was_swimming != is_swimming:
		queue_redraw()


func _process_goo(delta: float) -> void:
	if goo_grid == null:
		return
	if Input.is_action_pressed("spew") and goo_reserve > 0.0:
		var aim := get_global_mouse_position() - global_position
		if aim.length_squared() < 64.0:
			aim = Vector2(Input.get_axis("move_left", "move_right"), Input.get_axis("move_up", "move_down"))
		var deposited: float = goo_grid.spew(global_position, aim, minf(SPEW_RATE * delta, goo_reserve))
		if deposited > 0.0:
			set_goo_reserve(goo_reserve - deposited)
			if aim.normalized().y > 0.55 and is_on_floor():
				recent_down_spew_time = 0.48
				down_spew_charge += deposited
	elif Input.is_action_pressed("gulp") and goo_reserve < MAX_GOO:
		var recovered: float = goo_grid.gulp(global_position, minf(GULP_RATE * delta, MAX_GOO - goo_reserve))
		if recovered > 0.0:
			set_goo_reserve(goo_reserve + recovered)


func set_goo_reserve(value: float) -> void:
	goo_reserve = clampf(value, 0.0, MAX_GOO)
	reserve_changed.emit(goo_reserve)


func take_jump_speed() -> float:
	if recent_down_spew_time > 0.0 and down_spew_charge >= BOOST_CHARGE_REQUIRED:
		recent_down_spew_time = 0.0
		down_spew_charge = 0.0
		return BOOST_JUMP_SPEED
	return JUMP_SPEED


func _draw() -> void:
	if is_swimming:
		draw_circle(Vector2.ZERO, 20.0, Color(0.2, 0.9, 0.78, 0.2))
		draw_arc(Vector2.ZERO, 18.0, 0.0, TAU, 24, Color(0.45, 1.0, 0.9, 0.8), 2.0)
	draw_circle(Vector2.ZERO, 14.0, Color("#b9f56a"))
	draw_circle(Vector2(-5, -3), 2.5, Color("#14213d"))
	draw_circle(Vector2(5, -3), 2.5, Color("#14213d"))
	draw_arc(Vector2(0, 3), 6.0, 0.15, PI - 0.15, 12, Color("#14213d"), 2.0)
