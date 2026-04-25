extends Node2D
@onready var answerText = $Label
@onready var block = $Block

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass
func set_answer(text):
	answerText.set_text(text);
