"""
AnswerRush — Python backend
Run: uvicorn index:socket_app --host 0.0.0.0 --port 3000 --reload
"""

import socketio
from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles
from game_room import GameRoom

# ── Socket.io + FastAPI setup ──────────────────────────────────────────────────
sio = socketio.AsyncServer(async_mode="asgi", cors_allowed_origins="*")
app = FastAPI()
socket_app = socketio.ASGIApp(sio, app)

# Serve the Godot HTML5 export at /
# Comment this out until you've actually run the Godot HTML5 export
# app.mount("/", StaticFiles(directory="../godot/export", html=True), name="game")

# ── In-memory state ────────────────────────────────────────────────────────────
rooms: dict[str, GameRoom] = {}         # roomCode  → GameRoom
player_rooms: dict[str, str]  = {}     # socket id → roomCode


# ── Connection lifecycle ───────────────────────────────────────────────────────
@sio.event
async def connect(sid, environ):
    print(f"[+] connected  {sid}")


@sio.event
async def disconnect(sid):
    print(f"[-] disconnected {sid}")
    code = player_rooms.pop(sid, None)
    if code and code in rooms:
        await rooms[code].player_left(sid)


# ── Lobby ──────────────────────────────────────────────────────────────────────
@sio.event
async def join_room(sid, data):
    code = data.get("roomCode", "").upper().strip()
    name = data.get("playerName", "Player")

    if not code:
        await sio.emit("error", {"message": "Room code required"}, to=sid)
        return

    if code not in rooms:
        rooms[code] = GameRoom(sio, code)

    room = rooms[code]
    if len(room.players) >= 4:
        await sio.emit("error", {"message": "Room is full (max 4)"}, to=sid)
        return

    await sio.enter_room(sid, code)
    player_rooms[sid] = code
    await room.add_player(sid, name)


# ── Real-time game events ──────────────────────────────────────────────────────
@sio.event
async def player_move(sid, data):
    code = player_rooms.get(sid)
    if code and code in rooms:
        rooms[code].update_position(sid, data)


@sio.event
async def player_attack(sid, data):
    code = player_rooms.get(sid)
    if code and code in rooms:
        await rooms[code].handle_attack(sid, data)


@sio.event
async def claim_point(sid, _data):
    """Client fires this at round end if it detects the local player is on the correct platform."""
    code = player_rooms.get(sid)
    if code and code in rooms:
        await rooms[code].award_point(sid)
