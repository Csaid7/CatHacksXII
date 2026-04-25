"""
AnswerRush — Python backend
Run: uvicorn index:socket_app --host 0.0.0.0 --port 3000 --reload
"""

import socketio
from fastapi import FastAPI
from game_room import GameRoom

# Socket.io handles WebSocket connections; FastAPI is the HTTP wrapper around it
sio = socketio.AsyncServer(async_mode="asgi", cors_allowed_origins="*")
app = FastAPI()
socket_app = socketio.ASGIApp(sio, app)

# Uncomment once you've exported the Godot project to godot/export/
# app.mount("/", StaticFiles(directory="../godot/export", html=True), name="game")

# rooms maps a 4-letter code to the GameRoom object managing that game
# player_rooms lets us quickly look up which room any connected socket belongs to
rooms: dict[str, GameRoom] = {}
player_rooms: dict[str, str] = {}


# ── Connection lifecycle ───────────────────────────────────────────────────────

@sio.event
async def connect(sid, environ):
    print(f"[+] connected  {sid}")


@sio.event
async def disconnect(sid):
    print(f"[disconnect] fired for {sid}")
    print(f"[disconnect] player_rooms currently: {player_rooms}")
    print(f"[disconnect] rooms currently: {list(rooms.keys())}")
    
    code = player_rooms.pop(sid, None)
    print(f"[disconnect] {sid} was in room: {code}")
    
    if code and code in rooms:
        room = rooms[code]
        await room.player_left(sid)
        print(f"[disconnect] players remaining in {code}: {list(room.players.keys())}")
        if not room.players:
            # Remove ALL player_rooms entries pointing to this dead room
            dead_sids = [s for s, c in player_rooms.items() if c == code]
            for dead_sid in dead_sids:
                print(f"[disconnect] purging ghost entry {dead_sid} -> {code}")
                player_rooms.pop(dead_sid, None)
            del rooms[code]
            print(f"[room] {code} deleted — no players remaining")
    
    print(f"[-] disconnected {sid}")


# ── Lobby ──────────────────────────────────────────────────────────────────────

@sio.event
async def join_room(sid, data):
    code = data.get("roomCode", "").strip().upper()
    name = data.get("playerName", "Anonymous").strip() or "Anonymous"

    if not code:
        await sio.emit("error", {"message": "Room code is required."}, to=sid)
        return

    if code not in rooms:
        rooms[code] = GameRoom(sio, code)

    room = rooms[code]

    if len(room.players) >= 4:
        await sio.emit("error", {"message": "Room is full."}, to=sid)
        return

    # Remove any stale player with the same name
    stale_sid = next(
        (s for s, p in room.players.items() if p["name"] == name),
        None
    )
    if stale_sid and stale_sid != sid:
        print(f"[join_room] evicting stale {name} ({stale_sid})")
        player_rooms.pop(stale_sid, None)
        await sio.disconnect(stale_sid)  # force-close the old socket
        await room.player_left(stale_sid)

    await sio.enter_room(sid, code)
    player_rooms[sid] = code
    await rooms[code].add_player(sid, name)
    print(f"[join_room] {name} joined {code}, now has {len(rooms[code].players)} players")


# ── Real-time game events ──────────────────────────────────────────────────────

@sio.event
async def player_move(sid, data):
    # Just update the stored position; the broadcast loop will relay it to other clients
    code = player_rooms.get(sid)
    if code and code in rooms:
        rooms[code].update_position(sid, data)


@sio.event
async def player_attack(sid, data):
    # The room checks who's within hit range and sends knockback only to those players
    code = player_rooms.get(sid)
    if code and code in rooms:
        await rooms[code].handle_attack(sid, data)


@sio.event
async def claim_point(sid, _):
    # Client fires this when it thinks the local player is on the correct platform at round end
    # award_point validates the claim (round active, not already scored this round)
    code = player_rooms.get(sid)
    if code and code in rooms:
        await rooms[code].award_point(sid)
