## Platform.gd — attach to a StaticBody2D scene
##
## Scene tree expected:
##   Platform (StaticBody2D)
##   ├── CollisionShape2D   (RectangleShape2D, e.g. 200×20)
##   ├── Area2D             ($Area2D) — same rect shape, for standing detection
##   │   └── CollisionShape2D
##   └── Label              ($Label) — displays the answer text

extends StaticBody2D

# ── Set by GameManager after instantiation ────────────────────────────────────
var platform_id: String  = ""    # "A" / "B" / "C" / "D"
var is_correct:  bool    = false

# ── Who is currently standing on this platform ────────────────────────────────
var _occupants: Array[Node] = []

@onready var label : Label = $Label
@onready var area  : Area2D = $Area2D


func _ready() -> void:
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)


# ── Called by GameManager ─────────────────────────────────────────────────────
func setup(pid: String, answer_text: String, correct: bool) -> void:
	platform_id = pid
	is_correct  = correct
	label.text  = "%s: %s" % [pid, answer_text]


# ── Occupancy tracking ────────────────────────────────────────────────────────
func _on_body_entered(body: Node) -> void:
	if body.is_in_group("players"):
		_occupants.append(body)


func _on_body_exited(body: Node) -> void:
	_occupants.erase(body)


func get_occupants() -> Array[Node]:
	return _occupants


# ── Visual feedback ───────────────────────────────────────────────────────────
func flash_correct() -> void:
	modulate = Color.LIME_GREEN
	await get_tree().create_timer(2.5).timeout
	modulate = Color.WHITE


func flash_wrong() -> void:
	modulate = Color.RED
	await get_tree().create_timer(2.5).timeout
	modulate = Color.WHITE
