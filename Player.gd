extends CharacterBody2D
enum STATES {IDLE, RUN, JUMP, PUNCH}

const SPEED = 300.0
const JUMP_VELOCITY = -600.0
@export var playerNum: int = 1
@onready var animation = $AnimatedSprite2D
@onready var state = STATES.IDLE
# Get the gravity from the project settings to be synced with RigidBody nodes.
var gravity = ProjectSettings.get_setting("physics/2d/default_gravity")


func _physics_process(delta):
	# Add the gravity.
	if not is_on_floor():
		velocity.y += gravity * delta
		
	if Input.is_action_just_pressed("attack" + str(playerNum)):
		
		state = STATES.PUNCH
		animation.play("punch")

	# Handle Jump.
	if Input.is_action_just_pressed("jump" + str(playerNum)) and is_on_floor():
		velocity.y = JUMP_VELOCITY
		state = STATES.JUMP
		animation.play("jump")

	# Get the input direction and handle the movement/deceleration.
	# As good practice, you should replace UI actions with custom gameplay actions.
	var direction = Input.get_axis("left" + str(playerNum), "right" + str(playerNum))
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


func _on_animated_sprite_2d_animation_finished():
	if state == STATES.JUMP or state == STATES.PUNCH:
		state = STATES.IDLE
