extends Node
@onready var questionText = $QuestionBox/Label
@onready var blockA = $BlockA
@onready var blockB = $BlockB
@onready var blockC = $BlockC
@onready var blockD = $BlockD
@onready var timer = $Timer
@onready var scores = [0,0,0,0]
@onready var answerBlocks = [blockA, blockB, blockC, blockD]
@export var correctBlock: int = 0

# Called when the node enters the scene tree for the first time.
func _ready():
	questionText.set_text("How many episodes of One Piece are there?")
	correctBlock = 2
	blockA.set_answer("48")
	blockB.set_answer("over 9,000")
	blockC.set_answer("1,158")
	blockD.set_answer("153")
	timer.start(7)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass


func _on_timer_timeout():
	print("Time's up")
	check_answers()
	
func newLevel():
	questionText.set_text("How many episodes of One Piece are there?")
	blockA.set_answer("1,158")
	blockB.set_answer("over 9,000")
	blockC.set_answer("48")
	blockD.set_answer("153")
	pass

func check_answers():
	for i in range(answerBlocks.size()):
		var block = answerBlocks[i]
		print("Checking answer")
		var bodies = block.block.get_node("Area2D").get_overlapping_bodies()
		print("Still checking...")
		for body in bodies:
			print(body.name)
			if body.is_in_group("players"):
				
				if i == correctBlock:
					print(body.name, " is correct!")
					# reward player
				else:
					print(body.name, " is wrong!")
					# punish player
