extends CharacterBody2D
enum STATES {IDLE, RUN, JUMP, PUNCH, HIT}

const SPEED = 300.0
const JUMP_VELOCITY = -600.0
@export var playerNum: int = 1
@onready var animation = $AnimatedSprite2D
@onready var punchHitBox = $PunchHitBox
@onready var punchTimer = $PunchTimer
@onready var state = STATES.IDLE
# Get the gravity from the project settings to be synced with RigidBody nodes.
var gravity = ProjectSettings.get_setting("physics/2d/default_gravity")
var facing = 1
func _ready():
	punchHitBox.monitoring = false

func _physics_process(delta):
	# Add the gravity.
	if not is_on_floor():
		velocity.y += gravity * delta
		
	if Input.is_action_just_pressed("attack" + str(playerNum)):
		state = STATES.PUNCH
		punchHitBox.position.x = 30 * facing
		punchHitBox.monitoring = true
		punchTimer.start(0.2)
		animation.play("punch")

	# Handle Jump.
	if Input.is_action_just_pressed("jump" + str(playerNum)) and is_on_floor():
		velocity.y = JUMP_VELOCITY
		state = STATES.JUMP
		animation.play("jump")

	# Get the input direction and handle the movement/deceleration.
	# As good practice, you should replace UI actions with custom gameplay actions.
	var direction = Input.get_axis("left" + str(playerNum), "right" + str(playerNum))
	if direction and state != STATES.HIT:
		velocity.x = direction * SPEED
		if direction < 0:
			$AnimatedSprite2D.flip_h = true
			facing = -1
		else:
			$AnimatedSprite2D.flip_h = false
			facing = 1
		state = STATES.RUN
		animation.play("run")
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		if state == STATES.RUN:
			state = STATES.IDLE
	if state == STATES.IDLE:
		animation.play("idle")
	move_and_slide()


func _on_animated_sprite_2d_animation_finished():
	if (state == STATES.JUMP or state == STATES.PUNCH) or state == STATES.HIT:
		print("animation finished")
		state = STATES.IDLE


func _on_punch_hitbox_body_entered(body):
	if body != self and body.has_method("apply_knockback"):
		var attack_dir = Vector2(facing, 0)
		var attacker_pos = global_position
		body.apply_knockback(attack_dir,attacker_pos)


func _on_punch_timer_timeout():
	punchHitBox.monitoring = false

func apply_knockback(attack_dir,attacker_pos):
	state = STATES.HIT
	var to_attacker = (attacker_pos - global_position).normalized()
	var dot = to_attacker.x * facing
	if dot < 0:
		animation.play("suckerPunched")
	else:
		animation.play("hit")
	velocity.x += attack_dir.x * 400
	velocity.y = -200
	move_and_slide()
