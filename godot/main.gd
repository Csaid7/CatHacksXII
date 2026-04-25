extends Node
@onready var questionText = $QuestionBox/Label
@onready var blockA       = $BlockA
@onready var blockB       = $BlockB
@onready var blockC       = $BlockC
@onready var blockD       = $BlockD
@onready var answerBlocks = [blockA, blockB, blockC, blockD]

# ── State ──────────────────────────────────────────────────────────────────────
var my_id:               String     = ""
var remote_players:      Dictionary = {}
var local_player                    = null
var correct_platform_id: String     = ""
var round_active:        bool       = false
var _claimed:            bool       = false
var current_scores:      Dictionary = {}

# ── HUD nodes ─────────────────────────────────────────────────────────────────
var _hud:          CanvasLayer
var _timer_label:  Label
var _score_label:  Label
var _result_label: Label  # shown ABOVE the question box after each round
var _restart_btn:  Button


func _ready():
	# keep this node processing input even when the tree is paused
	# without this, pressing P to unpause would never be detected
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_hud()
	NetworkManager.room_updated.connect(_on_room_updated)
	NetworkManager.game_starting.connect(_on_game_starting)
	NetworkManager.round_started.connect(_on_round_started)
	NetworkManager.tick.connect(_on_tick)
	NetworkManager.state_updated.connect(_on_state_updated)
	NetworkManager.round_result_received.connect(_on_round_result)
	NetworkManager.game_over_received.connect(_on_game_over)


func _build_hud():
	_hud = CanvasLayer.new()
	_hud.layer = 10
	add_child(_hud)

	_timer_label = Label.new()
	_timer_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_timer_label.position             = Vector2(-110, 12)
	_timer_label.custom_minimum_size  = Vector2(100, 30)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_timer_label.text = ""
	_hud.add_child(_timer_label)

	_score_label = Label.new()
	_score_label.position = Vector2(12, 12)
	_score_label.text     = ""
	_hud.add_child(_score_label)

	# Controls — under the timer, top-right
	var controls_label = Label.new()
	controls_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	controls_label.position             = Vector2(-160, 44)
	controls_label.custom_minimum_size  = Vector2(150, 0)
	controls_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	controls_label.add_theme_font_size_override("font_size", 11)
	controls_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	controls_label.text = "Move: ← / →\nJump: Space\nPunch: X"
	_hud.add_child(controls_label)

	# Result label — sits ABOVE the question box (y=0, very top of screen)
	_result_label = Label.new()
	_result_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_result_label.position             = Vector2(0, 0)
	_result_label.custom_minimum_size  = Vector2(0, 30)
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_label.text = ""
	# bright background so it stands out above the question
	_result_label.add_theme_color_override("font_color", Color(1, 1, 0))
	_hud.add_child(_result_label)

	# Restart button — hidden until game over
	_restart_btn = Button.new()
	_restart_btn.set_anchors_preset(Control.PRESET_CENTER)
	_restart_btn.position = Vector2(-80, 60)
	_restart_btn.text     = "Play Again"
	_restart_btn.visible  = false
	_restart_btn.pressed.connect(_on_restart_pressed)
	_hud.add_child(_restart_btn)


# ── Claim-point detection ──────────────────────────────────────────────────────
func _process(_delta):
	if not round_active or local_player == null or _claimed:
		return
	if not local_player.is_on_floor():
		return

	var block_map     = {"A": blockA, "B": blockB, "C": blockC, "D": blockD}
	var correct_block = block_map.get(correct_platform_id)
	if correct_block == null:
		return

	var px = local_player.position.x
	var py = local_player.position.y
	var bx = correct_block.position.x
	var by = correct_block.position.y

	if abs(px - bx) < 90 and abs(py - by) < 80:
		_claimed = true
		NetworkManager.claim_point()


# ── Room management ────────────────────────────────────────────────────────────
func _on_room_updated(players: Array, your_id: String, _player_count: int):
	if your_id != "":
		my_id = your_id

	remote_players.clear()
	local_player = null

	for i in players.size():
		var p     = players[i]
		var pid   = p.get("id", "")
		var pnode = get_node_or_null("Player" + str(i + 1))
		if pnode == null:
			continue
		if pid == my_id:
			pnode.is_local = true
			local_player   = pnode
		else:
			pnode.is_local = false
			remote_players[pid] = pnode

		var color_hex  = p.get("color", "ffffff")
		pnode.modulate = Color("#" + color_hex)


# ── Round flow ─────────────────────────────────────────────────────────────────
func _on_game_starting(countdown: int):
	questionText.set_text("Game starting in %d..." % countdown)
	_result_label.text  = ""
	_score_label.text   = ""
	_restart_btn.visible = false


func _on_round_started(round: int, max_rounds: int, question: String, platforms: Array):
	questionText.set_text("Round %d / %d\n%s" % [round, max_rounds, question])
	correct_platform_id  = ""
	round_active         = true
	_claimed             = false
	# clear the result label above the question at the start of each new round
	_result_label.text   = ""

	# Respawn local player at their scene-defined starting position
	if local_player != null:
		local_player.respawn()

	for block in answerBlocks:
		block.reset_highlight()

	for platform in platforms:
		var id         = platform.get("id", "")
		var label      = platform.get("label", "")
		var is_correct = platform.get("isCorrect", false)
		match id:
			"A": blockA.set_answer(label)
			"B": blockB.set_answer(label)
			"C": blockC.set_answer(label)
			"D": blockD.set_answer(label)
		if is_correct:
			correct_platform_id = id


func _on_tick(time_left: int):
	_timer_label.text = ":%02d" % time_left
	if time_left <= 5:
		_timer_label.modulate = Color(1.0, 0.3, 0.3)
	else:
		_timer_label.modulate = Color(1.0, 1.0, 1.0)


# ── State sync ─────────────────────────────────────────────────────────────────
func _on_state_updated(players: Array):
	for p in players:
		var pid = p.get("id", "")
		if pid == my_id:
			continue
		if pid in remote_players:
			var node = remote_players[pid]
			node.apply_remote_state(
				p.get("x",      node.position.x),
				p.get("y",      node.position.y),
				p.get("facing", 1)
			)


# ── End of round / game ────────────────────────────────────────────────────────
func _on_round_result(correct_id: String, scores: Dictionary):
	round_active   = false
	current_scores = scores

	var block_map = {"A": blockA, "B": blockB, "C": blockC, "D": blockD}
	for id in block_map:
		if id == correct_id:
			block_map[id].flash_correct()
		else:
			block_map[id].flash_wrong()

	# Show who got it right ABOVE the question text
	var scores_text = "  ".join(
		scores.keys().map(func(name): return "%s %d" % [name, scores[name]])
	)
	_result_label.text = "✓ %s correct!   %s" % [correct_id, scores_text]

	_update_score_label(scores)


func _on_game_over(winner: String, final_scores: Dictionary):
	round_active      = false
	_timer_label.text = ""

	var lines = ["🏆  %s wins!\n" % winner]
	for name in final_scores:
		lines.append("%s  —  %d pts" % [name, final_scores[name]])
	questionText.set_text("\n".join(lines))

	_result_label.text   = ""
	_restart_btn.visible = true   # show the Play Again button
	_update_score_label(final_scores)


# ── Restart ────────────────────────────────────────────────────────────────────
func _on_restart_pressed():
	# tell the server to restart the game in this room
	NetworkManager.restart_game()
	_restart_btn.visible = false
	_result_label.text   = ""
	_score_label.text    = ""


# ── Helpers ────────────────────────────────────────────────────────────────────
func _update_score_label(scores: Dictionary):
	var lines = []
	for name in scores:
		lines.append("%s  %d" % [name, scores[name]])
	_score_label.text = "\n".join(lines)
