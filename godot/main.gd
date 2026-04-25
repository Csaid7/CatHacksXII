extends Node
@onready var questionText = $QuestionBox/Label
@onready var blockA       = $BlockA
@onready var blockB       = $BlockB
@onready var blockC       = $BlockC
@onready var blockD       = $BlockD
@onready var answerBlocks = [blockA, blockB, blockC, blockD]

# States
var my_id:               String     = ""
var remote_players:      Dictionary = {}
var local_player                    = null
var correct_platform_id: String     = ""
var round_active:        bool       = false
var _claimed:            bool       = false
var current_scores:      Dictionary = {}

# HUD nodes
var _hud:          CanvasLayer
var _timer_label:  Label
var _score_label:  Label
var _result_label: Label
var _restart_btn:  Button


func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Draw the background image behind all game elements
	var bg_layer = CanvasLayer.new()
	bg_layer.layer = -10
	add_child(bg_layer)
	var bg = TextureRect.new()
	bg.texture      = load("res://CatHacksBackgroundImg-01.png")
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg_layer.add_child(bg)

	# Assign distinct colors to each answer platform
	blockA.set_base_color(Color(1.0,  0.35, 0.35))  # red
	blockB.set_base_color(Color(0.35, 0.6,  1.0))   # blue
	blockC.set_base_color(Color(1.0,  0.85, 0.2))   # yellow
	blockD.set_base_color(Color(0.35, 1.0,  0.45))  # green

	# Make the question label readable over any background
	questionText.add_theme_color_override("font_color", Color.WHITE)
	questionText.add_theme_color_override("font_outline_color", Color.BLACK)
	questionText.add_theme_constant_override("outline_size", 6)

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
	_timer_label.add_theme_color_override("font_color", Color.WHITE)
	_timer_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_timer_label.add_theme_constant_override("outline_size", 6)
	_timer_label.add_theme_font_size_override("font_size", 20)
	_hud.add_child(_timer_label)

	_score_label = Label.new()
	_score_label.position = Vector2(12, 12)
	_score_label.text     = ""
	_score_label.add_theme_color_override("font_color", Color.WHITE)
	_score_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_score_label.add_theme_constant_override("outline_size", 5)
	_hud.add_child(_score_label)

	var controls_label = Label.new()
	controls_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	controls_label.position             = Vector2(-160, 44)
	controls_label.custom_minimum_size  = Vector2(150, 0)
	controls_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	controls_label.add_theme_font_size_override("font_size", 11)
	controls_label.add_theme_color_override("font_color", Color.WHITE)
	controls_label.add_theme_color_override("font_outline_color", Color.BLACK)
	controls_label.add_theme_constant_override("outline_size", 4)
	controls_label.text = "Move: Arrow Keys\nJump: Space\nPunch: X"
	_hud.add_child(controls_label)

	_result_label = Label.new()
	_result_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_result_label.position             = Vector2(0, 0)
	_result_label.custom_minimum_size  = Vector2(0, 30)
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_label.text = ""
	_result_label.add_theme_color_override("font_color", Color(1, 1, 0))
	_result_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_result_label.add_theme_constant_override("outline_size", 6)
	_hud.add_child(_result_label)

	_restart_btn = Button.new()
	_restart_btn.set_anchors_preset(Control.PRESET_CENTER)
	_restart_btn.position = Vector2(-80, 60)
	_restart_btn.text     = "Play Again"
	_restart_btn.visible  = false
	_restart_btn.pressed.connect(_on_restart_pressed)
	_hud.add_child(_restart_btn)


func _process(_delta):
	pass


# Map each player in the server list to a Player1-4 node in the scene.
func _on_room_updated(players: Array, your_id: String, _player_count: int):
	if your_id != "":
		my_id = your_id

	for i in players.size():
		var p     = players[i]
		var pid   = p.get("id",    "")
		var color = p.get("color", "ffffff")
		var node  = get_node_or_null("Player%d" % (i + 1))
		if node == null:
			continue
		node.set_player_color(color)
		if pid == my_id:
			if local_player == null:
				local_player = node
				node.is_local = true
		else:
			node.is_local = false
			if not remote_players.has(pid):
				remote_players[pid] = node


func _on_game_starting(_countdown: int):
	pass


func _on_round_started(round: int, max_rounds: int, question: String, platforms: Array):
	questionText.set_text("Round %d / %d\n%s" % [round, max_rounds, question])
	round_active        = true
	_claimed            = false
	_result_label.text  = ""

	if local_player != null:
		local_player.respawn()

	for block in answerBlocks:
		block.reset_highlight()

	for platform in platforms:
		var id    = platform.get("id",    "")
		var label = platform.get("label", "")
		match id:
			"A": blockA.set_answer(label)
			"B": blockB.set_answer(label)
			"C": blockC.set_answer(label)
			"D": blockD.set_answer(label)


func _on_tick(time_left: int):
	_timer_label.text = "%d" % time_left


func _on_state_updated(players: Array):
	for p in players:
		var pid = p.get("id", "")
		if pid == my_id:
			continue
		var node = remote_players.get(pid)
		if node:
			node.apply_remote_state(
				p.get("x",      0.0),
				p.get("y",      0.0),
				p.get("facing", 1)
			)


func _on_round_result(correct_id: String, scores: Dictionary):
	round_active        = false
	_claimed            = false
	correct_platform_id = correct_id

	for block_id in ["A", "B", "C", "D"]:
		var block = _block_by_id(block_id)
		if block == null:
			continue
		if block_id == correct_id:
			block.flash_correct()
		else:
			block.flash_wrong()

	var lines: Array = []
	for pname in scores:
		lines.append("%s: %d" % [pname, scores[pname]])
	_score_label.text = "\n".join(lines)
	current_scores    = scores


func _on_game_over(winner: String, final_scores: Dictionary):
	round_active       = false
	_result_label.text = "Game Over!  Winner: %s" % winner

	var lines: Array = []
	for pname in final_scores:
		lines.append("%s: %d" % [pname, final_scores[pname]])
	_score_label.text = "\n".join(lines)

	_restart_btn.visible = true


func _on_restart_pressed():
	_restart_btn.visible = false
	NetworkManager._emit_js("restart_game", {})


func _on_timer_timeout():
	pass


func _block_by_id(id: String):
	match id:
		"A": return blockA
		"B": return blockB
		"C": return blockC
		"D": return blockD
	return null
