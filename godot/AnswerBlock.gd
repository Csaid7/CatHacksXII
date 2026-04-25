extends Node2D
@onready var answerText = $Label
@onready var block      = $Block

var _base_color: Color = Color(1, 1, 1)


func _ready():
	pass


func set_answer(text: String):
	answerText.set_text(text)


# Called from main.gd to give each platform its unique color.
func set_base_color(color: Color):
	_base_color = color
	modulate    = color


# Flash bright green for the correct answer, then fade back to the platform color.
func flash_correct():
	modulate = Color(0.3, 1.0, 0.3)
	var t = create_tween()
	t.tween_interval(2.0)
	t.tween_property(self, "modulate", _base_color, 0.5)


# Flash red for a wrong answer, then fade back to the platform color.
func flash_wrong():
	modulate = Color(1.0, 0.35, 0.35)
	var t = create_tween()
	t.tween_interval(2.0)
	t.tween_property(self, "modulate", _base_color, 0.5)


# Snap back to the platform color at the start of each round.
func reset_highlight():
	modulate = _base_color
