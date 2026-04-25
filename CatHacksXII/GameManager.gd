extends Node

var remote_players = {}

@export var player_scene: PackedScene

func _ready():
	randomize()
	# Clear any leftover remote players from a previous session
	_clear_remote_players()
	
	if NetworkManager.on_state_update.is_connected(_on_state_update):
		NetworkManager.on_state_update.disconnect(_on_state_update)
	NetworkManager.on_state_update.connect(_on_state_update)
	NetworkManager.my_id = get_unique_id()
	
func get_unique_id() -> String:
	return str(randi())

func _clear_remote_players():
	for id in remote_players:
		if remote_players[id] and is_instance_valid(remote_players[id]):
			remote_players[id].queue_free()
	remote_players.clear()

func _on_state_update(data: Dictionary):
	var players: Array = data.get("players", [])
	var current_ids = {}

	# Build current IDs
	for p in players:
		current_ids[p["id"]] = true

	# Remove stale players
	for id in remote_players.keys():
		if not current_ids.has(id):
			var node = remote_players[id]
			if is_instance_valid(node):
				node.queue_free()
			remote_players.erase(id)

	# Update/create players
	for p in players:
		var id = p["id"]
		if id == NetworkManager.my_id or current_ids.has(id) == false:
			continue

		if not remote_players.has(id):
			var remote = Node2D.new()
			var sprite = ColorRect.new()
			sprite.size = Vector2(32, 64)
			sprite.color = Color.RED
			sprite.position = Vector2(-16, -64)
			remote.add_child(sprite)

			var collision = CollisionShape2D.new()
			collision.shape = RectangleShape2D.new()
			collision.shape.size = Vector2(32, 64)
			remote.add_child(collision)

			add_child(remote)
			remote_players[id] = remote
			remote.position = Vector2(p["x"], p["y"])  # No lerp on spawn
		else:
			var node = remote_players[id]
			var target = Vector2(p["x"], p["y"])
			node.position = lerp(node.position, target, 0.3)
