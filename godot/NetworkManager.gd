extends Node

# Emitted when the server sends back the current lobby state
signal room_updated(players: Array, your_id: String, player_count: int)

# Emitted once the server starts the countdown before the first round
signal game_starting(countdown: int)

# Emitted at the start of each round with the question and platform data
signal round_started(round: int, max_rounds: int, question: String, platforms: Array)

# Emitted every second with the remaining time
signal tick(time_left: int)

# Emitted ~20x/sec with every player's current position
signal state_updated(players: Array)

# Emitted to a specific player when they get hit
signal knockback_received(direction: int)

# Emitted at the end of each round with the correct platform and scores
signal round_result_received(correct_platform_id: String, scores: Dictionary)

# Emitted when all rounds are done
signal game_over_received(winner: String, final_scores: Dictionary)

# Set this to your Railway URL in production; localhost for local testing
const SERVER_URL = "http://localhost:3000"

var _js_available := false


func _ready() -> void:
	# JavaScriptBridge only exists in HTML5 exports — skip setup in the editor
	if not OS.has_feature("web"):
		print("[NetworkManager] Not running in browser — socket disabled")
		return
	_js_available = true
	_setup_socket()


func _setup_socket() -> void:
	# The socket_inject.html already loads Socket.io and creates window.socket.
	# Here we attach listeners that push events into a queue GDScript can drain.
	JavaScriptBridge.eval("""
		window._gdEvents = [];
		function _pushEvent(name, data) {
			window._gdEvents.push({ event: name, data: data });
		}
		socket.on('room_update',    function(d) { _pushEvent('room_update', d); });
		socket.on('game_starting',  function(d) { _pushEvent('game_starting', d); });
		socket.on('round_start',    function(d) { _pushEvent('round_start', d); });
		socket.on('tick',           function(d) { _pushEvent('tick', d); });
		socket.on('state_update',   function(d) { _pushEvent('state_update', d); });
		socket.on('apply_knockback',function(d) { _pushEvent('apply_knockback', d); });
		socket.on('round_result',   function(d) { _pushEvent('round_result', d); });
		socket.on('game_over',      function(d) { _pushEvent('game_over', d); });
	""")


func _process(_delta: float) -> void:
	if not _js_available:
		return
	# Drain the JS event queue each frame and fire the matching GDScript signal
	var raw = JavaScriptBridge.eval("JSON.stringify(window._gdEvents.splice(0))")
	if not raw or raw == "null":
		return
	var events = JSON.parse_string(raw)
	if not events:
		return
	for ev in events:
		_dispatch(ev["event"], ev["data"])


func _dispatch(event: String, data: Variant) -> void:
	match event:
		"room_update":
			room_updated.emit(
				data.get("players", []),
				data.get("yourId", ""),
				data.get("playerCount", 0)
			)
		"game_starting":
			game_starting.emit(data.get("countdown", 3))
		"round_start":
			round_started.emit(
				data.get("round", 0),
				data.get("maxRounds", 15),
				data.get("question", ""),
				data.get("platforms", [])
			)
		"tick":
			tick.emit(data.get("timeLeft", 0))
		"state_update":
			state_updated.emit(data.get("players", []))
		"apply_knockback":
			knockback_received.emit(data.get("direction", 1))
		"round_result":
			round_result_received.emit(
				data.get("correctPlatformId", ""),
				data.get("scores", {})
			)
		"game_over":
			game_over_received.emit(
				data.get("winner", ""),
				data.get("finalScores", {})
			)


# ── Outbound events ────────────────────────────────────────────────────────────

func join_room(room_code: String, player_name: String) -> void:
	_emit_js("join_room", {"roomCode": room_code, "playerName": player_name})

# Call this every frame (or whenever position changes) while in a game
func send_move(x: float, y: float, vy: float, facing: int) -> void:
	_emit_js("player_move", {"x": x, "y": y, "vy": vy, "facing": facing})

func send_attack(facing: int) -> void:
	_emit_js("player_attack", {"facing": facing})

# Fire when the local player is standing on what they think is the correct platform
func claim_point() -> void:
	_emit_js("claim_point", {})

func restart_game() -> void:
	_emit_js("restart_game", {})


func _emit_js(event: String, data: Dictionary) -> void:
	if not _js_available:
		return
	var json_data = JSON.stringify(data)
	JavaScriptBridge.eval("socket.emit('%s', %s)" % [event, json_data])
