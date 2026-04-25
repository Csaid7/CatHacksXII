extends Node2D
@onready var answerText = $Label
@onready var block      = $Block

var _base_color: Color = Color(1, 1, 1)


func _ready():
	# White bold text with a thick black outline so it reads over any background.
	answerText.add_theme_color_override("font_color", Color.WHITE)
	answerText.add_theme_color_override("font_outline_color", Color.BLACK)
	answerText.add_theme_constant_override("outline_size", 6)
	answerText.add_theme_font_size_override("font_size", 18)


func set_answer(text: String):
	answerText.set_text(text)


# Called from main.gd to give each platform its unique color.
# Only tint the block sprite — leave the label unaffected.
func set_base_color(color: Color):
	_base_color  = color
	block.modulate = color


# Flash bright green for the correct answer, then fade back to the platform color.
func flash_correct():
	block.modulate = Color(0.3, 1.0, 0.3)
	var t = create_tween()
	t.tween_interval(2.0)
	t.tween_property(block, "modulate", _base_color, 0.5)


# Flash red for a wrong answer, then fade back to the platform color.
func flash_wrong():
	block.modulate = Color(1.0, 0.35, 0.35)
	var t = create_tween()
	t.tween_interval(2.0)
	t.tween_property(block, "modulate", _base_color, 0.5)


# Snap back to the platform color at the start of each round.
func reset_highlight():
	block.modulate = _base_color
