"""
AnswerRush — Python backend
Run: uvicorn index:socket_app --host 0.0.0.0 --port 3000 --reload
"""

import asyncio
import socketio
from fastapi import FastAPI, Request
from starlette.middleware.base import BaseHTTPMiddleware
from fastapi.staticfiles import StaticFiles
from game_room import GameRoom


class CrossOriginIsolationMiddleware(BaseHTTPMiddleware):
    """
    Adds the two headers browsers require for SharedArrayBuffer / secure-context
    features used by Godot's HTML5 export.  Works over plain HTTP on a LAN.
    """
    async def dispatch(self, request: Request, call_next):
        response = await call_next(request)
        response.headers["Cross-Origin-Opener-Policy"]   = "same-origin"
        response.headers["Cross-Origin-Embedder-Policy"] = "credentialless"
        return response


# Socket.io handles WebSocket connections; FastAPI is the HTTP wrapper around it
sio = socketio.AsyncServer(async_mode="asgi", cors_allowed_origins="*")
app = FastAPI()
app.add_middleware(CrossOriginIsolationMiddleware)
socket_app = socketio.ASGIApp(sio, app)

# Serve the exported Godot game as static files
app.mount("/", StaticFiles(directory="../godot/export", html=True), name="game")

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
    # Find and remove the player from whatever room they were in
    code = player_rooms.pop(sid, None)
    if code and code in rooms:
        room = rooms[code]
        await room.player_left(sid)
        # Clean up the room object once the last player leaves
        if not room.players:
            del rooms[code]
    print(f"[-] disconnected {sid}")


# ── Lobby ──────────────────────────────────────────────────────────────────────

@sio.event
async def join_room(sid, data):
    # Normalize the code so "abc ", "ABC", and "abc" all hit the same room
    code = data.get("roomCode", "").strip().upper()
    name = data.get("playerName", "Anonymous").strip() or "Anonymous"

    if not code:
        await sio.emit("error", {"message": "Room code is required."}, to=sid)
        return

    # Hard cap of 4 players per room
    if code in rooms and len(rooms[code].players) >= 4:
        await sio.emit("error", {"message": "Room is full."}, to=sid)
        return

    # Create the room on first join
    if code not in rooms:
        rooms[code] = GameRoom(sio, code)

    # enter_room puts this socket into a Socket.io "room" so we can emit to everyone at once
    await sio.enter_room(sid, code)
    player_rooms[sid] = code
    await rooms[code].add_player(sid, name)


# ── Lobby control ─────────────────────────────────────────────────────────────

@sio.event
async def start_game(sid, data=None):
    print(f"[start_game] received from {sid}")
    code = player_rooms.get(sid)
    if not code or code not in rooms:
        print(f"[start_game] room not found for {sid}")
        return
    room = rooms[code]
    if sid != room.host_sid:
        print(f"[start_game] rejected — {sid} is not host ({room.host_sid})")
        await sio.emit("error", {"message": "Only the host can start the game."}, to=sid)
        return
    if room.round_active or room.round_num > 0:
        print(f"[start_game] rejected — game already running")
        return
    print(f"[start_game] starting game in room {code}")
    asyncio.create_task(room.start_game())


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
    code = player_rooms.get(sid)
    if code and code in rooms:
        await rooms[code].award_point(sid)


@sio.event
async def restart_game(sid, _):
    # any player in the room can trigger a restart after game over
    code = player_rooms.get(sid)
    if code and code in rooms:
        await rooms[code].restart()
