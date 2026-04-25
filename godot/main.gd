extends Node

# ── Scene node references ─────────────────────────────────────────────────────
# @onready means these get assigned when the scene loads
# the $ is shorthand for get_node() — finds a child node by name
@onready var questionText  = $QuestionBox/Label
@onready var blockA        = $BlockA
@onready var blockB        = $BlockB
@onready var blockC        = $BlockC
@onready var blockD        = $BlockD
@onready var timer         = $Timer
@onready var timerLabel    = $HUD/TimerLabel    # shows countdown on screen
@onready var scoreLabel    = $HUD/ScoreLabel    # shows scores on screen
@onready var localPlayer   = $Players/Player1   # the player THIS browser controls
@onready var remotePlayer  = $Players/Player2   # the opponent — moved by network data

# maps answer block id ("A","B","C","D") to the actual node
var answerBlocks = {}

# track scores locally so we can display them
var scores = {}

# the correct platform id for the current round — set when round_start arrives
var correct_platform_id = ""


func _ready():
	# build the lookup dictionary so we can find blocks by id easily
	answerBlocks = {"A": blockA, "B": blockB, "C": blockC, "D": blockD}

	# ── Connect to NetworkManager signals ────────────────────────
	# NetworkManager is an Autoload singleton — available everywhere
	# .connect() says "when this signal fires, call this function"
	# This replaces the hardcoded test data Kiara had here
	if OS.get_name() == "Web":
		NetworkManager.round_started.connect(_on_round_start)
		NetworkManager.tick_received.connect(_on_tick)
		NetworkManager.state_updated.connect(_on_state_update)
		NetworkManager.knockback_received.connect(_on_knockback)
		NetworkManager.round_result_received.connect(_on_round_result)
		NetworkManager.game_over_received.connect(_on_game_over)

		# join the room — for now uses a hardcoded code, lobby screen will replace this
		NetworkManager.join_room("ROOM1", "Player")
	else:
		# running in Godot editor — show test data so Kiara can still preview the scene
		questionText.set_text("How many episodes of One Piece are there?")
		blockA.set_answer("1,158")
		blockB.set_answer("over 9,000")
		blockC.set_answer("48")
		blockD.set_answer("153")


# ── Server → Godot handlers ───────────────────────────────────────────────────

func _on_round_start(data: Dictionary):
	# server sent the question and 4 platform positions
	# data = { round, maxRounds, question, platforms: [{id, label, isCorrect, x, y}] }
	questionText.set_text(data["question"])

	# update each answer block's label with the text from the server
	for platform in data["platforms"]:
		var id    = platform["id"]     # "A", "B", "C", or "D"
		var label = platform["label"]  # the answer text
		if answerBlocks.has(id):
			answerBlocks[id].set_answer(label)

	# remember which platform is correct so we can check at round end
	correct_platform_id = ""
	for platform in data["platforms"]:
		if platform["isCorrect"]:
			correct_platform_id = platform["id"]

	# restart the visual timer
	timer.start(15)


func _on_tick(data: Dictionary):
	# server sends { timeLeft } every second
	# update the timer label on screen
	timerLabel.set_text(str(data["timeLeft"]) + "s")


func _on_state_update(data: Dictionary):
	# server sends all players' positions ~20x/sec
	# data = { players: [{id, x, y, facing}] }
	for player_data in data["players"]:
		# only move the REMOTE player — the local player moves from input
		# if we moved the local player from network data it would feel laggy
		if player_data["id"] != NetworkManager.my_id:
			# lerp = linear interpolation — smoothly slide to target position
			# instead of snapping, which looks jittery
			remotePlayer.position = remotePlayer.position.lerp(
				Vector2(player_data["x"], player_data["y"]),
				0.2  # 0.2 = 20% of the way there each frame — adjust for feel
			)
			# flip sprite to face the right direction
			remotePlayer.get_node("AnimatedSprite2D").flip_h = player_data["facing"] < 0


func _on_knockback(data: Dictionary):
	# server says the local player got hit
	# data = { direction: 1 or -1 }
	localPlayer.receive_knockback(data["direction"])


func _on_round_result(data: Dictionary):
	# server says the round ended
	# data = { correctPlatformId, scores }
	scores = data["scores"]
	# highlight the correct answer block
	if answerBlocks.has(data["correctPlatformId"]):
		# you can add a visual effect here — for now just update score label
		pass
	# update score display
	var score_text = ""
	for name in scores:
		score_text += name + ": " + str(scores[name]) + "  "
	scoreLabel.set_text(score_text)
	# tell the server we're on the correct platform if we are
	# (claim_point is validated server-side so it's safe to always send)
	NetworkManager.claim_point()


func _on_game_over(data: Dictionary):
	# server says the game is done
	# data = { winner, finalScores }
	questionText.set_text("WINNER: " + data["winner"] + "!")


func _on_timer_timeout():
	# local timer hit 0 — visual only, server is the real authority
	timerLabel.set_text("0s")
