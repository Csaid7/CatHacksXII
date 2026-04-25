import asyncio
import random
from question_gen import generate_question

# Fixed world positions of the A/B/C/D answer blocks in the Godot scene (from main.tscn).
# Used at round-end to check which players are standing on the correct platform.
ANSWER_BLOCK_POSITIONS = {
    "A": {"x": 102,  "y": 460},
    "B": {"x": 380,  "y": 322},
    "C": {"x": 712,  "y": 185},
    "D": {"x": 1020, "y": 328},
}

# Starting positions matching the Player1-4 nodes in main.tscn.
# Used when resetting player positions at the start of each round.
PLAYER_STARTS = [
    {"x": 419, "y": 412},
    {"x": 491, "y": 412},
    {"x": 567, "y": 410},
    {"x": 648, "y": 404},
]

# Y coordinate below which a player is considered to have fallen off the map.
# The floor in Godot sits at y≈643; anything past 750 is clearly off-screen.
FALL_THRESHOLD = 750

MAX_ROUNDS  = 15
ROUND_TIME  = 15   # seconds
RESULT_WAIT = 3    # pause between rounds so players can read the result


class GameRoom:
    def __init__(self, sio, room_code: str):
        self.sio          = sio
        self.room_code    = room_code
        self.players      = {}     # sid → {name, x, y, facing, score, number}
        self.host_sid     = None   # first player to join; only they can start the game
        self.round_num    = 0
        self.time_left    = ROUND_TIME
        self.current_q    = None
        self._timer       = None   # asyncio Task for the countdown
        self._broadcast   = None   # asyncio Task for the position stream
        self.round_active = False
        self._fallen      = set()  # sids that have fallen off this round

    # ------------------------------------------------------------------
    # Lobby
    # ------------------------------------------------------------------

    async def add_player(self, sid: str, name: str):
        number = len(self.players) + 1
        if self.host_sid is None:
            self.host_sid = sid   # first joiner is the host
        start  = PLAYER_STARTS[number - 1]
        self.players[sid] = {
            "name":   name,
            "x":      start["x"],
            "y":      start["y"],
            "facing": 1,
            "score":  0,
            "number": number,
        }
        await self._broadcast_room_update(sid)

    async def player_left(self, sid: str):
        self.players.pop(sid, None)
        if self._timer:
            self._timer.cancel()
        if self._broadcast:
            self._broadcast.cancel()
        if self.players:
            await self.sio.emit(
                "player_left",
                {"playerCount": len(self.players)},
                room=self.room_code,
            )

    async def _broadcast_room_update(self, new_sid: str):
        payload = {
            "players":     self._players_list(),
            "playerCount": len(self.players),
        }
        await self.sio.emit("room_update", payload, room=self.room_code, skip_sid=new_sid)
        await self.sio.emit("room_update", {**payload, "yourId": new_sid}, to=new_sid)

    # ------------------------------------------------------------------
    # Game flow
    # ------------------------------------------------------------------

    async def start_game(self):
        countdown = 3
        await self.sio.emit("game_starting", {"countdown": countdown}, room=self.room_code)
        await asyncio.sleep(countdown)
        self.current_q = generate_question()
        await self._start_round()

    async def _start_round(self):
        self.round_num += 1
        self.time_left  = ROUND_TIME
        self._fallen    = set()   # everyone is alive again at the start of each round

        # Reset all player positions to their starting spots.
        # Clients teleport the local player themselves (Player.gd respawn());
        # remote players snap via the first state_update broadcast.
        for sid, player in self.players.items():
            start = PLAYER_STARTS[player["number"] - 1]
            player["x"] = start["x"]
            player["y"] = start["y"]

        await self.sio.emit("round_start", {
            "round":     self.round_num,
            "maxRounds": MAX_ROUNDS,
            "question":  self.current_q["question"],
            "platforms": self.current_q["platforms"],
        }, room=self.room_code)

        self._broadcast   = asyncio.create_task(self._broadcast_loop())
        self._timer       = asyncio.create_task(self._run_timer())
        self.round_active = True

    async def _run_timer(self):
        try:
            while self.time_left > 0:
                await asyncio.sleep(1)
                self.time_left -= 1
                await self.sio.emit("tick", {"timeLeft": self.time_left}, room=self.room_code)
            await self._end_round()
        except asyncio.CancelledError:
            pass

    async def _broadcast_loop(self):
        try:
            while True:
                await self.sio.emit(
                    "state_update",
                    {"players": self._players_list()},
                    room=self.room_code,
                )
                await asyncio.sleep(1 / 20)
        except asyncio.CancelledError:
            pass

    async def _end_round(self):
        self._broadcast.cancel()
        self.round_active = False

        correct_id = self.current_q["correct"]
        block_pos  = ANSWER_BLOCK_POSITIONS.get(correct_id)

        # Award a point to every player who is standing on the correct platform right now.
        # "On the platform" = within ±90 px horizontally and within the vertical band
        # just above the block (the player's feet rest above the block's centre).
        if block_pos:
            bx, by = block_pos["x"], block_pos["y"]
            for sid, player in self.players.items():
                if sid in self._fallen:
                    continue
                dx = abs(player["x"] - bx)
                dy = player["y"] - by          # negative means player is above block
                if dx < 90 and -120 < dy < 20:
                    player["score"] += 1

        await self.sio.emit("round_result", {
            "correctPlatformId": correct_id,
            "scores": {p["name"]: p["score"] for p in self.players.values()},
        }, room=self.room_code)

        await asyncio.sleep(RESULT_WAIT)

        if self.round_num >= MAX_ROUNDS:
            await self._end_game()
        else:
            self.current_q = generate_question()
            await self._start_round()

    async def _end_game(self):
        ranked = sorted(self.players.values(), key=lambda p: p["score"], reverse=True)
        await self.sio.emit("game_over", {
            "winner":      ranked[0]["name"],
            "finalScores": {p["name"]: p["score"] for p in self.players.values()},
        }, room=self.room_code)

    # ------------------------------------------------------------------
    # Real-time updates from clients
    # ------------------------------------------------------------------

    def update_position(self, sid: str, data: dict):
        player = self.players.get(sid)
        if not player:
            return
        player["x"]      = data.get("x",      player["x"])
        player["y"]      = data.get("y",      player["y"])
        player["facing"] = data.get("facing", player["facing"])

        # Mark players who have fallen off the map — permanent for this round
        if player["y"] > FALL_THRESHOLD:
            self._fallen.add(sid)

    async def handle_attack(self, sid: str, data: dict):
        attacker = self.players.get(sid)
        if not attacker:
            return
        facing = data.get("facing", attacker["facing"])

        for target_sid, target in self.players.items():
            if target_sid == sid:
                continue
            dx = abs(attacker["x"] - target["x"])
            dy = abs(attacker["y"] - target["y"])
            if dx < 90 and dy < 70:
                await self.sio.emit("apply_knockback", {"direction": facing}, to=target_sid)

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------

    def _players_list(self):
        return [
            {
                "id":     sid,
                "name":   p["name"],
                "x":      p["x"],
                "y":      p["y"],
                "facing": p["facing"],
                "score":  p["score"],
            }
            for sid, p in self.players.items()
        ]
