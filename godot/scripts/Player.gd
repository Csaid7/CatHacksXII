## Player.gd — attach to a CharacterBody2D scene
##
## Scene tree expected:
##   Player (CharacterBody2D)
##   ├── Sprite2D          ($Sprite2D)
##   ├── CollisionShape2D  (CapsuleShape2D or RectangleShape2D)
##   └── Label             ($NameLabel)  ← shows player name above head

extends CharacterBody2D

# ── Tuning constants (from TEAM_GUIDE.md) ─────────────────────────────────────
const SPEED          := 280.0
const JUMP_VELOCITY  := -650.0
const GRAVITY        := 2000.0
const KNOCKBACK      := Vector2(750.0, -250.0)
const STUN_DURATION  := 0.4
const ATTACK_X       := 90.0   # attack range horizontal
const ATTACK_Y       := 70.0   # attack range vertical
const SEND_RATE      := 0.05   # send position every 50 ms (20×/sec)

# ── Public properties (set by GameManager when spawning) ──────────────────────
var player_id: String = ""
var player_name: String = "Player"
var is_local: bool = false       # true only for the player on this browser tab
var facing: int = 1              # 1 = right, -1 = left

# ── Private state ─────────────────────────────────────────────────────────────
var _stunned: bool = false
var _send_timer: float = 0.0

@onready var sprite     : Sprite2D = $Sprite2D
@onready var name_label : Label    = $NameLabel


func _ready() -> void:
	name_label.text = player_name
	# Colour-code players so they're easy to tell apart
	var colours := [Color.CYAN, Color.ORANGE_RED, Color.LIME_GREEN, Color.YELLOW]
	var idx := (int(player_id[-1]) - 1) % colours.size() if player_id else 0
	modulate = colours[idx]


# ── Physics loop (local player only) ──────────────────────────────────────────
func _physics_process(delta: float) -> void:
	if not is_local:
		return

	# Gravity
	if not is_on_floor():
		velocity.y += GRAVITY * delta

	if not _stunned:
		# Horizontal movement
		var dir := Input.get_axis("move_left", "move_right")
		velocity.x = dir * SPEED
		if dir != 0:
			facing = int(sign(dir))
			sprite.flip_h = facing < 0

		# Jump — only from the floor
		if Input.is_action_just_pressed("jump") and is_on_floor():
			velocity.y = JUMP_VELOCITY

		# Fast fall
		if Input.is_action_pressed("fast_fall") and not is_on_floor():
			velocity.y += GRAVITY * delta

	move_and_slide()

	# Throttled position broadcast
	_send_timer -= delta
	if _send_timer <= 0.0:
		_send_timer = SEND_RATE
		NetworkManager.send_position(global_position, velocity.y, facing)


# ── Input (attack key) ────────────────────────────────────────────────────────
func _unhandled_input(event: InputEvent) -> void:
	if not is_local or _stunned:
		return
	if event.is_action_pressed("attack"):
		NetworkManager.send_attack(facing)


# ── Called by server via NetworkManager ───────────────────────────────────────
func receive_knockback(direction: int) -> void:
	velocity = Vector2(direction * KNOCKBACK.x, KNOCKBACK.y)
	_stunned = true
	get_tree().create_timer(STUN_DURATION).timeout.connect(func(): _stunned = false)


# ── Called by GameManager for remote players ──────────────────────────────────
func set_remote_state(pos: Vector2, face: int) -> void:
	global_position = global_position.lerp(pos, 0.2)   # smooth interpolation
	if face != facing:
		facing = face
		sprite.flip_h = facing < 0
