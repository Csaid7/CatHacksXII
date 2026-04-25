extends Node
@onready var questionText = $QuestionBox/Label
@onready var blockA = $BlockA
@onready var blockB = $BlockB
@onready var blockC = $BlockC
@onready var blockD = $BlockD
@onready var timer = $Timer
@onready var scores = [0,0,0,0]
@onready var answerBlocks = [blockA, blockB, blockC, blockD]

# Set by Lobby.gd (and confirmed here) once the server assigns our socket id.
var my_id: String = ""

# Maps each remote player's socket id → their Player node in the scene.
# Built in _on_room_updated so state_update knows where to move them.
var remote_players: Dictionary = {}


func _ready():
	NetworkManager.room_updated.connect(_on_room_updated)
	NetworkManager.game_starting.connect(_on_game_starting)
	NetworkManager.round_started.connect(_on_round_started)
	NetworkManager.tick.connect(_on_tick)
	NetworkManager.state_updated.connect(_on_state_updated)
	NetworkManager.round_result_received.connect(_on_round_result)
	NetworkManager.game_over_received.connect(_on_game_over)


func _process(_delta):
	pass


func _on_timer_timeout():
	pass


# ── Room management ────────────────────────────────────────────────────────────

func _on_room_updated(players: Array, your_id: String, player_count: int):
	# yourId is only included the first time (when we join).
	# On subsequent updates (other players joining) the server omits it,
	# so guard against overwriting the correctly-set my_id with an empty string.
	if your_id != "":
		my_id = your_id

	remote_players.clear()

	# Players arrive in join order. Slot them into Player1…Player4 by index.
	for i in players.size():
		var p     = players[i]
		var pid   = p.get("id", "")
		var pnode = get_node_or_null("Player" + str(i + 1))
		if pnode == null:
			continue
		if pid == my_id:
			pnode.is_local = true
		else:
			pnode.is_local = false
			remote_players[pid] = pnode


# ── Round flow ─────────────────────────────────────────────────────────────────

func _on_game_starting(countdown: int):
	questionText.set_text("Game starting in %d..." % countdown)


func _on_round_started(round: int, max_rounds: int, question: String, platforms: Array):
	questionText.set_text("Round %d/%d\n%s" % [round, max_rounds, question])
	for platform in platforms:
		match platform.get("id", ""):
			"A": blockA.set_answer(platform.get("label", ""))
			"B": blockB.set_answer(platform.get("label", ""))
			"C": blockC.set_answer(platform.get("label", ""))
			"D": blockD.set_answer(platform.get("label", ""))


func _on_tick(time_left: int):
	# TODO: update a visible timer label if you add one to the scene
	pass


# ── State sync ─────────────────────────────────────────────────────────────────

func _on_state_updated(players: Array):
	for p in players:
		var pid = p.get("id", "")
		if pid == my_id:
			continue  # our own position is driven by local physics, not the server
		if pid in remote_players:
			var node = remote_players[pid]
			node.apply_remote_state(
				p.get("x", node.position.x),
				p.get("y", node.position.y),
				p.get("facing", 1)
			)


# ── End of round / game ────────────────────────────────────────────────────────

func _on_round_result(correct_platform_id: String, result_scores: Dictionary):
	# Highlight which block was correct in the question text
	questionText.set_text("Correct: %s" % correct_platform_id)
	# TODO: visually highlight the correct answer block and update a score label


func _on_game_over(winner: String, final_scores: Dictionary):
	questionText.set_text("%s wins!" % winner)
