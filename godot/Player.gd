extends CharacterBody2D
enum STATES {IDLE, RUN, JUMP, PUNCH}

const SPEED = 300.0
const JUMP_VELOCITY = -600.0
@export var playerNum: int = 1
@onready var animation = $AnimatedSprite2D
@onready var state = STATES.IDLE
var gravity = ProjectSettings.get_setting("physics/2d/default_gravity")

# Tracks the last remote x so we can detect movement for animations.
var _prev_remote_x: float = 0.0

# Stored so we can restore collision after hiding for unassigned slots.
var _orig_layer: int = 0
var _orig_mask:  int = 0

# Scene-defined starting position saved before we hide the node.
var _spawn_position: Vector2

# Set to true by main.gd once the server tells us which player id is ours.
var is_local: bool = false:
	set(value):
		is_local = value
		_show()


func _ready():
	_spawn_position = position
	_orig_layer = collision_layer
	_orig_mask  = collision_mask
	visible         = false
	collision_layer = 0
	collision_mask  = 0
	animation.speed_scale = 2.5
	NetworkManager.knockback_received.connect(_on_knockback)


func _show():
	visible         = true
	collision_layer = _orig_layer
	collision_mask  = _orig_mask


# Teleport back to scene starting position and zero velocity.
func respawn():
	position = _spawn_position
	velocity  = Vector2.ZERO


# Apply the server-assigned hex color as a sprite tint.
func set_player_color(hex: String):
	modulate = Color.html(hex)


func _physics_process(delta):
	# Remote players are positioned via apply_remote_state — skip input here.
	if not is_local:
		return

	if not is_on_floor():
		velocity.y += gravity * delta

	if Input.is_action_just_pressed("attack1"):
		state = STATES.PUNCH
		animation.play("punch")
		var facing = -1 if animation.flip_h else 1
		NetworkManager.send_attack(facing)

	if Input.is_action_just_pressed("jump1") and is_on_floor():
		velocity.y = JUMP_VELOCITY
		state = STATES.JUMP
		animation.play("jump")

	var direction = Input.get_axis("left1", "right1")
	if direction:
		velocity.x = direction * SPEED
		animation.flip_h = direction < 0
		state = STATES.RUN
		animation.play("run")
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		if state == STATES.RUN:
			state = STATES.IDLE
	if state == STATES.IDLE:
		animation.play("idle")

	move_and_slide()

	var facing = -1 if animation.flip_h else 1
	NetworkManager.send_move(position.x, position.y, velocity.y, facing)


func apply_remote_state(rx: float, ry: float, rfacing: int):
	if not visible:
		_show()
	var dx = abs(rx - _prev_remote_x)
	_prev_remote_x = rx
	position.x = rx
	position.y = ry
	animation.flip_h = rfacing < 0
	if state != STATES.PUNCH:
		if dx > 2.0:
			state = STATES.RUN
			animation.play("run")
		else:
			state = STATES.IDLE
			animation.play("idle")


func _on_knockback(direction: int):
	velocity.x = direction * 500
	velocity.y = -300
