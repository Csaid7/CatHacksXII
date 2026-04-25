extends CharacterBody2D
enum STATES {IDLE, RUN, JUMP, PUNCH}

const SPEED = 300.0
const JUMP_VELOCITY = -600.0
@export var playerNum: int = 1
@onready var animation = $AnimatedSprite2D
@onready var state = STATES.IDLE
var gravity = ProjectSettings.get_setting("physics/2d/default_gravity")

# Set to true by main.gd once the server tells us which player id is ours.
# Only the local player reads keyboard input; remote players are driven by state_update.
var is_local: bool = false

# Tracks the last remote x position so we can detect movement for animations.
var _prev_remote_x: float = 0.0


func _ready():
	NetworkManager.knockback_received.connect(_on_knockback)


func _physics_process(delta):
	# Remote players are positioned via apply_remote_state() — skip all input here.
	if not is_local:
		return

	# Gravity
	if not is_on_floor():
		velocity.y += gravity * delta

	# Always use slot "1" controls — on your own screen you are always player 1.
	# (playerNum drives which node you ARE in the scene, not which keys you press.)

	# Attack
	if Input.is_action_just_pressed("attack1"):
		state = STATES.PUNCH
		animation.play("punch")
		var facing = -1 if $AnimatedSprite2D.flip_h else 1
		NetworkManager.send_attack(facing)

	# Jump
	if Input.is_action_just_pressed("jump1") and is_on_floor():
		velocity.y = JUMP_VELOCITY
		state = STATES.JUMP
		animation.play("jump")

	# Horizontal movement
	var direction = Input.get_axis("left1", "right1")
	if direction:
		velocity.x = direction * SPEED
		$AnimatedSprite2D.flip_h = direction < 0
		state = STATES.RUN
		animation.play("run")
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		if state == STATES.RUN:
			state = STATES.IDLE
	if state == STATES.IDLE:
		animation.play("idle")

	move_and_slide()

	# Send position to server every physics frame.
	var facing = -1 if $AnimatedSprite2D.flip_h else 1
	NetworkManager.send_move(position.x, position.y, velocity.y, facing)


# Called by main.gd ~20x/sec to sync a remote player's position and animation.
func apply_remote_state(rx: float, ry: float, rfacing: int):
	var dx = abs(rx - _prev_remote_x)
	_prev_remote_x = rx
	position.x = rx
	position.y = ry
	$AnimatedSprite2D.flip_h = rfacing < 0
	# Only update animation if not mid-punch (let punch finish naturally).
	if state != STATES.PUNCH:
		if dx > 2.0:
			state = STATES.RUN
			animation.play("run")
		else:
			state = STATES.IDLE
			animation.play("idle")


# Called by NetworkManager when the server says this player was hit.
func _on_knockback(direction: int):
	velocity = Vector2(direction * 750, -250)


func _on_animated_sprite_2d_animation_finished():
	if state == STATES.JUMP or state == STATES.PUNCH:
		state = STATES.IDLE
