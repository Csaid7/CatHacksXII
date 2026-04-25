extends Node

var my_id: String = ""

signal on_room_update(data: Dictionary)
signal on_game_starting(data: Dictionary)
signal on_round_start(data: Dictionary)
signal on_state_update(data: Dictionary)
signal on_tick(data: Dictionary)
signal on_round_result(data: Dictionary)
signal on_game_over(data: Dictionary)
signal on_apply_knockback(data: Dictionary)
signal on_player_left(data: Dictionary)
signal on_error(data: Dictionary)

func _process(_delta):
	if OS.get_name() != "Web":
		return
	# Read and clear the JS event queue every frame
	var count = JavaScriptBridge.eval("window._gameEvents.length", true)
	if count == null or int(count) == 0:
		return
	for i in range(int(count)):
		var raw = JavaScriptBridge.eval("window._gameEvents[%d]" % i, true)
		if raw == null:
			continue
		var parsed = JSON.parse_string(raw)
		if not parsed is Dictionary:
			continue
		print("dispatching: ", parsed.get("type", "?"))  # ADD THIS
		_dispatch(parsed)
	JavaScriptBridge.eval("window._gameEvents = []")
	# Keep my_id updated
	var id = JavaScriptBridge.eval("window._myId", true)
	if id != null and id != "":
		my_id = id

func _dispatch(event: Dictionary):
	var type = event.get("type", "")
	var data = event.get("data", {})
	if not data is Dictionary:
		data = {}
	match type:
		"room_update":     on_room_update.emit(data)
		"game_starting":   on_game_starting.emit(data)
		"round_start":     on_round_start.emit(data)
		"state_update":    on_state_update.emit(data)
		"tick":            on_tick.emit(data)
		"round_result":    on_round_result.emit(data)
		"game_over":       on_game_over.emit(data)
		"apply_knockback": on_apply_knockback.emit(data)
		"player_left":     on_player_left.emit(data)
		"error":           on_error.emit(data)

func join_room(room_code: String, player_name: String):
	JavaScriptBridge.eval("window._joinRoom('%s', '%s')" % [room_code, player_name])

func send_position(pos: Vector2, vel_y: float, facing: int):
	JavaScriptBridge.eval("window._sendMove(%f, %f, %f, %d)" % [pos.x, pos.y, vel_y, facing])

func send_attack(facing: int):
	JavaScriptBridge.eval("window._socket.emit('player_attack', {facing: %d})" % facing)

func claim_point():
	JavaScriptBridge.eval("window._socket.emit('claim_point', {})")
