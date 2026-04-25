extends CanvasLayer

@onready var question_label : Label = $QuestionLabel
@onready var timer_bar : ProgressBar = $TimerBar
@onready var score_label : Label = $ScoreLabel
@onready var result_label : Label = $ResultLabel

const ROUND_TIME = 15.0


# Called when the node enters the scene tree for the first time.
func _ready():
	result_label.visible = false
	NetworkManager.on_round_start.connect(_on_round_start)
	NetworkManager.on_tick.connect(_on_tick)
	NetworkManager.on_round_result.connect(_on_round_result)
	NetworkManager.on_state_update.connect(_on_state_update)
	
func _on_round_start(data: Dictionary):
	question_label.text = data.get("question", "")
	timer_bar.max_value = ROUND_TIME
	timer_bar.value = ROUND_TIME
	result_label.visible = false
	var round_num = data.get("round", 1)
	var max_rounds = data.get("maxRounds", 15)
	
	print("Round %d / %d" %[round_num, max_rounds])
	
func _on_tick(data: Dictionary):
	timer_bar.value = float(data.get("timeLeft", 0))
	
func _on_round_result(data: Dictionary):
	var scores: Dictionary = data.get("scores", {})
	var parts = []
	for name in scores:
		parts.append("%s: %d" % [name, scores[name]])
	score_label.text = " | ".join(parts)
	result_label.visible = true
	result_label.text = "Correct " + _correct_label(data)
	
func _on_state_update(data: Dictionary):
	
	var players: Array = data.get("players", [])
	var parts = []
	for p in players:
		parts.append("%s: %d" % [p["name"], p["score"]])
	score_label.text = "  |  ".join(parts)

func _correct_label(data: Dictionary) -> String:
	return "Correct platform: " + data.get("correctPlatformId", "?")
