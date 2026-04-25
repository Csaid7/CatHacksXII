## GameManager.gd — attach to the root Game node
##
## Owns round flow, player spawning, platform spawning, and HUD updates.
## Talks to the server only through NetworkManager signals.
##
## Scene tree expected (Game.tscn):
##   Game (Node2D)
##   ├── GameManager  ← this script
##   ├── Platforms    (Node2D container)
##   ├── Players      (Node2D container)
##   └── HUD (CanvasLayer)
##       ├── QuestionLabel  (Label)
##       ├── TimerLabel     (Label)
##       ├── RoundLabel     (Label)
##       └── ScoreContainer (VBoxContainer) ← children added dynamically

extends Node

const PLAYER_SCENE   := preload("res://scenes/Player.tscn")
const PLATFORM_SCENE := preload("res://scenes/Platform.tscn")

# ── HUD references ────────────────────────────────────────────────────────────
@onready var question_label  : Label       = $HUD/QuestionLabel
@onready var timer_label     : Label       = $HUD/TimerLabel
@onready var round_label     : Label       = $HUD/RoundLabel
@onready var score_container : VBoxContainer = $HUD/ScoreContainer
@onready var platforms_node  : Node2D      = $Platforms
@onready var players_node    : Node2D      = $Players

# ── Runtime state ─────────────────────────────────────────────────────────────
var player_nodes : Dictionary = {}   # socket id → Player node
var platform_nodes : Dictionary = {} # platform id ("A"…"D") → Platform node
var correct_platform_id : String = ""
var round_active : bool = false


func _ready() -> void:
	# Connect to NetworkManager signals
	NetworkManager.round_started.connect(_on_round_start)
	NetworkManager.state_updated.connect(_on_state_update)
	NetworkManager.knockback_received.connect(_on_knockback)
	NetworkManager.tick_received.connect(_on_tick)
	NetworkManager.round_result.connect(_on_round_result)
	NetworkManager.game_over.connect(_on_game_over)
	NetworkManager.room_updated.connect(_on_room_update)


# ── Lobby: spawn player nodes when server confirms who's in the room ──────────
func _on_room_update(data: Dictionary) -> void:
	for p in data.players:
		if p.id in player_nodes:
			continue   # already spawned

		var node : Node = PLAYER_SCENE.instantiate()
		node.player_id   = p.id
		node.player_name = p.name
		node.is_local    = (p.id == NetworkManager.my_id)
		players_node.add_child(node)
		node.global_position = Vector2(p.x, p.y)
		node.add_to_group("players")
		player_nodes[p.id] = node


# ── Round start ───────────────────────────────────────────────────────────────
func _on_round_start(data: Dictionary) -> void:
	round_active = true
	correct_platform_id = ""   # we learn this at round_result time
	question_label.text = data.question
	round_label.text    = "Round %d / %d" % [data.round, data.maxRounds]
	timer_label.modulate = Color.WHITE

	_spawn_platforms(data.platforms)


func _spawn_platforms(platforms: Array) -> void:
	# Clear previous platforms
	for child in platforms_node.get_children():
		child.queue_free()
	platform_nodes.clear()

	for pd in platforms:
		var node : Node = PLATFORM_SCENE.instantiate()
		platforms_node.add_child(node)
		node.global_position = Vector2(pd.x, pd.y)
		node.setup(pd.id, pd.label, pd.isCorrect)
		platform_nodes[pd.id] = node


# ── Position sync (20×/sec from server) ──────────────────────────────────────
func _on_state_update(players: Array) -> void:
	for p in players:
		if p.id == NetworkManager.my_id:
			continue   # local player drives itself
		var node = player_nodes.get(p.id)
		if node:
			node.set_remote_state(Vector2(p.x, p.y), p.facing)


# ── Knockback on local player ─────────────────────────────────────────────────
func _on_knockback(direction: int) -> void:
	var local_node = player_nodes.get(NetworkManager.my_id)
	if local_node:
		local_node.receive_knockback(direction)


# ── Timer tick ────────────────────────────────────────────────────────────────
func _on_tick(time_left: int) -> void:
	timer_label.text = str(time_left)
	timer_label.modulate = Color.RED if time_left <= 3 else Color.WHITE

	# At round end (time_left == 0) check if local player deserves a point
	if time_left == 0:
		_check_local_player_platform()


func _check_local_player_platform() -> void:
	if not round_active:
		return
	var local_node = player_nodes.get(NetworkManager.my_id)
	if not local_node:
		return

	for pid in platform_nodes:
		var plat = platform_nodes[pid]
		if local_node in plat.get_occupants() and plat.is_correct:
			NetworkManager.claim_point()
			break


# ── Round result ──────────────────────────────────────────────────────────────
func _on_round_result(data: Dictionary) -> void:
	round_active = false
	correct_platform_id = data.correctPlatformId

	# Flash platforms
	for pid in platform_nodes:
		var plat = platform_nodes[pid]
		if plat.is_correct:
			plat.flash_correct()
		else:
			plat.flash_wrong()

	# Update scoreboard
	_update_scores(data.scores)


func _update_scores(scores: Dictionary) -> void:
	for child in score_container.get_children():
		child.queue_free()

	for sid in scores:
		var node = player_nodes.get(sid)
		var name_str = node.player_name if node else sid
		var lbl := Label.new()
		lbl.text = "%s: %d" % [name_str, scores[sid]]
		score_container.add_child(lbl)


# ── Game over ─────────────────────────────────────────────────────────────────
func _on_game_over(data: Dictionary) -> void:
	question_label.text = "🏆 %s wins!" % data.winner
	timer_label.text    = ""
	round_label.text    = "Game over"
	# TODO: show a proper end screen / restart button
