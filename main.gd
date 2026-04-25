extends Node
@onready var questionText = $QuestionBox/Label
@onready var blockA = $BlockA
@onready var blockB = $BlockB
@onready var blockC = $BlockC
@onready var blockD = $BlockD
@onready var timer = $Timer
@onready var scores = [0,0,0,0]
@onready var answerBlocks = [blockA, blockB, blockC, blockD]

# Called when the node enters the scene tree for the first time.
func _ready():
	questionText.set_text("How many episodes of One Piece are there?")
	blockA.set_answer("1,158")
	blockB.set_answer("over 9,000")
	blockC.set_answer("48")
	blockD.set_answer("153")
	#timer.start(15)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass


func _on_timer_timeout():
	pass # Replace with function body.
