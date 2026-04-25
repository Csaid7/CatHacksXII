extends CharacterBody2D

enum STATES {IDLE, RUN, JUMP, PUNCH}

const SPEED        = 300.0
const JUMP_VELOCITY = -600.0

# KNOCKBACK constants — must match ATTACK_X and ATTACK_Y in server/game_room.py
const KNOCKBACK_FORCE = Vector2(750, -250)
const STUN_DURATION   = 0.4  # seconds — prevents counter-spam after being hit

# playerNum drives input actions like "jump1", "left1", "attack1"
@export var playerNum: int = 1

# is_local_player = true  → this is the player YOU control in THIS browser tab
# is_local_player = false → this is the remote opponent, moved by network data
@export var is_local_player: bool = true

@onready var animation = $AnimatedSprite2D
@onready var state     = STATES.IDLE

var gravity    = ProjectSettings.get_setting("physics/2d/default_gravity")
var stun_timer = 0.0  # counts down — player can't act while > 0
var facing     = 1    # 1 = right, -1 = left — sent to server for knockback direction

# throttle how often we send position to the server
# 20 times per second (every 0.05s) keeps traffic reasonable
const SEND_RATE  = 0.05
var   send_timer = 0.0


func _physics_process(delta):
	# ── Remote player ─────────────────────────────────────────────
	# If this is the opponent, their position comes from the server via state_update.
	# main.gd listens for that signal and moves this node directly.
	# We still apply gravity so they fall correctly on our screen.
	if not is_local_player:
		if not is_on_floor():
			velocity.y += gravity * delta
		move_and_slide()
		return  # skip all input handling below

	# ── Stun ──────────────────────────────────────────────────────
	# After being knocked back, the player is frozen briefly
	if stun_timer > 0:
		stun_timer -= delta
		move_and_slide()
		return  # can't move or attack while stunned

	# ── Gravity ───────────────────────────────────────────────────
	if not is_on_floor():
		velocity.y += gravity * delta

	# ── Attack ────────────────────────────────────────────────────
	if Input.is_action_just_pressed("attack" + str(playerNum)):
		state = STATES.PUNCH
		animation.play("punch")
		# tell the server we punched — it validates range server-side
		# and sends apply_knockback to whoever is close enough
		if OS.get_name() == "Web":
			NetworkManager.send_attack(facing)

	# ── Jump ──────────────────────────────────────────────────────
	if Input.is_action_just_pressed("jump" + str(playerNum)) and is_on_floor():
		velocity.y = JUMP_VELOCITY
		state = STATES.JUMP
		animation.play("jump")

	# ── Horizontal movement ───────────────────────────────────────
	var direction = Input.get_axis("left" + str(playerNum), "right" + str(playerNum))
	if direction:
		velocity.x = direction * SPEED
		facing = 1 if direction > 0 else -1
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

	# ── Send position to server ~20x/sec ─────────────────────────
	send_timer += delta
	if send_timer >= SEND_RATE and OS.get_name() == "Web":
		send_timer = 0.0
		NetworkManager.send_position(position.x, position.y, facing)


# Called by main.gd when the server sends apply_knockback to this player
func receive_knockback(direction: int):
	# direction = 1 or -1 (which way the attacker was facing)
	velocity   = Vector2(KNOCKBACK_FORCE.x * direction, KNOCKBACK_FORCE.y)
	stun_timer = STUN_DURATION
	state      = STATES.IDLE


func _on_animated_sprite_2d_animation_finished():
	if state == STATES.JUMP or state == STATES.PUNCH:
		state = STATES.IDLE
