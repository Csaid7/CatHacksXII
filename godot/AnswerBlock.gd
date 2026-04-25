extends Node2D
@onready var answerText = $Label
@onready var block      = $Block


func _ready():
	pass


func set_answer(text: String):
	answerText.set_text(text)


# Flash green for the correct answer, then fade back to normal.
func flash_correct():
	modulate = Color(0.3, 1.0, 0.3)
	var t = create_tween()
	t.tween_interval(2.0)
	t.tween_property(self, "modulate", Color(1, 1, 1), 0.5)


# Flash red for a wrong answer block, then fade back to normal.
func flash_wrong():
	modulate = Color(1.0, 0.35, 0.35)
	var t = create_tween()
	t.tween_interval(2.0)
	t.tween_property(self, "modulate", Color(1, 1, 1), 0.5)


# Immediately snap back to normal (called at the start of each round).
func reset_highlight():
	modulate = Color(1, 1, 1)
