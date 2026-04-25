extends Node

# socket holds the Socket.io connection object from the browser
# it starts empty and gets filled in _ready() when the game loads
var socket

# my_id is the socket ID the server assigns us on connect
# main.gd uses it to tell which player in state_update is the local one
var my_id: String = ""

# callbacks MUST be stored as member variables
# if they were local variables they'd get garbage collected and listeners would stop working
var _cb_room_update
var _cb_game_starting
var _cb_round_start
var _cb_tick
var _cb_state_update
var _cb_apply_knockback
var _cb_round_result
var _cb_game_over

# signals let other scripts in Godot react to server events
# instead of NetworkManager directly controlling main.gd, it fires a signal
# and any script that cares can connect to it
signal room_updated(data)
signal game_starting(data)
signal round_started(data)
signal tick_received(data)
signal state_updated(data)
signal knockback_received(data)
signal round_result_received(data)
signal game_over_received(data)

func _ready():
	# OS.get_name() tells us what platform the game is running on
	# "Web" means browser — JavaScriptBridge only exists there, not in the editor
	if OS.get_name() == "Web":
		# grab the socket.io connection that was created in index.html
		# window._socket was set up before Godot even loaded
		socket = JavaScriptBridge.eval("window._socket")
		# now set up all the listeners so we hear server events
		_setup_listeners()

func _setup_listeners():
	# for each event:
	# 1. wrap our GDScript handler with create_callback() so JS can call it
	# 2. store it in a member variable so it doesn't get garbage collected
	# 3. tell socket.io to call it when that event arrives

	_cb_room_update = JavaScriptBridge.create_callback(_on_room_update)
	socket.call("on", "room_update", _cb_room_update)

	_cb_game_starting = JavaScriptBridge.create_callback(_on_game_starting)
	socket.call("on", "game_starting", _cb_game_starting)

	_cb_round_start = JavaScriptBridge.create_callback(_on_round_start)
	socket.call("on", "round_start", _cb_round_start)

	_cb_tick = JavaScriptBridge.create_callback(_on_tick)
	socket.call("on", "tick", _cb_tick)

	_cb_state_update = JavaScriptBridge.create_callback(_on_state_update)
	socket.call("on", "state_update", _cb_state_update)

	_cb_apply_knockback = JavaScriptBridge.create_callback(_on_apply_knockback)
	socket.call("on", "apply_knockback", _cb_apply_knockback)

	_cb_round_result = JavaScriptBridge.create_callback(_on_round_result)
	socket.call("on", "round_result", _cb_round_result)

	_cb_game_over = JavaScriptBridge.create_callback(_on_game_over)
	socket.call("on", "game_over", _cb_game_over)

# ── Handlers (server → Godot) ─────────────────────────────────────────────────
# each handler receives args[] from JavaScript
# args[0] is always the data the server sent, serialized as a string
# we parse it back into a GDScript dictionary then fire a signal

func _on_room_update(args):
	# server sent updated player list — also contains yourId so we know who we are
	var data = JSON.parse_string(args[0])
	if data.has("yourId"):
		my_id = data["yourId"]  # store our socket ID so main.gd can use it
	emit_signal("room_updated", data)

func _on_game_starting(args):
	# server is counting down before the first round
	var data = JSON.parse_string(args[0])
	emit_signal("game_starting", data)

func _on_round_start(args):
	# server sent the question + platform positions for this round
	var data = JSON.parse_string(args[0])
	emit_signal("round_started", data)

func _on_tick(args):
	# server sent the current time remaining in the round
	var data = JSON.parse_string(args[0])
	emit_signal("tick_received", data)

func _on_state_update(args):
	# server sent all players current positions
	var data = JSON.parse_string(args[0])
	emit_signal("state_updated", data)

func _on_apply_knockback(args):
	# server says our player got hit — data has the knockback direction
	var data = JSON.parse_string(args[0])
	emit_signal("knockback_received", data)

func _on_round_result(args):
	# server says the round ended — has correct platform and scores
	var data = JSON.parse_string(args[0])
	emit_signal("round_result_received", data)

func _on_game_over(args):
	# server says the game is over — has winner and final scores
	var data = JSON.parse_string(args[0])
	emit_signal("game_over_received", data)

# ── Senders (Godot → server) ──────────────────────────────────────────────────
# these functions are called by other scripts to send data to the server
# we serialize the data to JSON then pass it to socket.emit via JavaScriptBridge

func join_room(room_code: String, player_name: String):
	# called from the lobby screen when the player enters a room code
	var payload = JSON.stringify({"roomCode": room_code, "playerName": player_name})
	JavaScriptBridge.eval("window._socket.emit('join_room', %s)" % payload)

func send_position(x: float, y: float, facing: int):
	# called every frame from Player.gd to tell the server where we are
	var payload = JSON.stringify({"x": x, "y": y, "facing": facing})
	JavaScriptBridge.eval("window._socket.emit('player_move', %s)" % payload)

func send_attack(facing: int):
	# called from Player.gd when the player punches
	var payload = JSON.stringify({"facing": facing})
	JavaScriptBridge.eval("window._socket.emit('player_attack', %s)" % payload)

func claim_point():
	# called from main.gd when the round ends and local player is on correct platform
	JavaScriptBridge.eval("window._socket.emit('claim_point', {})")
