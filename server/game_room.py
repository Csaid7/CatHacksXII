import asyncio
import random
from question_gen import generate_question

# Platform layout — server assigns positions so all clients agree
PLATFORM_POSITIONS = [
    {"x": 150, "y": -420},
    {"x": 450, "y": -420},
    {"x": 250, "y": -230},
    {"x": 550, "y": -230},
]

MAX_ROUNDS  = 15
ROUND_TIME  = 15   # seconds
RESULT_WAIT = 3    # seconds between rounds


class GameRoom:
    def __init__(self, sio, room_code: str):
        self.sio        = sio
        self.room_code  = room_code
        self.players    = {}   # sid → {name, x, y, facing, score, number}
        self.round_num  = 0
        self.time_left  = ROUND_TIME
        self.current_q  = None
        self.next_q     = None
        self._timer     = None
        self._broadcast = None

    # ------------------------------------------------------------------
    # Lobby
    # ------------------------------------------------------------------

    async def add_player(self, sid: str, name: str):
        number = len(self.players) + 1
        self.players[sid] = {
            "name":    name,
            "x":       200 + number * 120,
            "y":       500,
            "facing":  1,
            "score":   0,
            "number":  number,
        }
        await self._broadcast_room_update(sid)

        if len(self.players) == 4:
            await self.start_game()

    async def player_left(self, sid: str):
        self.players.pop(sid, None)
        if self._timer:
            self._timer.cancel()
        if self._broadcast:
            self._broadcast.cancel()

    async def _broadcast_room_update(self, new_sid: str):
        await self.sio.emit("room_update", {
            "players":     self._players_list(),
            "yourId":      new_sid,
            "playerCount": len(self.players),
        }, to=self.room_code)

    # ------------------------------------------------------------------
    # Game flow
    # ------------------------------------------------------------------

    async def start_game(self):
        await self.sio.emit("game_starting", {"countdown": 3}, to=self.room_code)
        await asyncio.sleep(3)
        self.current_q = await generate_question()
        await self._start_round()

    async def _start_round(self):
        self.round_num += 1
        self.time_left  = ROUND_TIME

        # Assign random positions to platforms so correct answer moves each round
        positions = random.sample(PLATFORM_POSITIONS, len(PLATFORM_POSITIONS))
        platforms_with_pos = [
            {**p, **positions[i]}
            for i, p in enumerate(self.current_q["platforms"])
        ]

        # Pre-fetch next question in the background while this round plays
        asyncio.create_task(self._prefetch_next())

        await self.sio.emit("round_start", {
            "round":     self.round_num,
            "maxRounds": MAX_ROUNDS,
            "question":  self.current_q["question"],
            "platforms": platforms_with_pos,
        }, to=self.room_code)

        self._broadcast = asyncio.create_task(self._broadcast_loop())
        self._timer     = asyncio.create_task(self._run_timer())

    async def _prefetch_next(self):
        self.next_q = await generate_question()

    async def _run_timer(self):
        while self.time_left > 0:
            await asyncio.sleep(1)
            self.time_left -= 1
            await self.sio.emit("tick", {"timeLeft": self.time_left}, to=self.room_code)
        await self._end_round()

    async def _broadcast_loop(self):
        """Push player positions to everyone at ~20 fps."""
        while True:
            await self.sio.emit("state_update", {
                "players": self._players_list()
            }, to=self.room_code)
            await asyncio.sleep(1 / 20)

    async def _end_round(self):
        if self._broadcast:
            self._broadcast.cancel()

        await self.sio.emit("round_result", {
            "correctPlatformId": self.current_q["correct"],
            "scores": {sid: p["score"] for sid, p in self.players.items()},
        }, to=self.room_code)

        await asyncio.sleep(RESULT_WAIT)

        if self.round_num >= MAX_ROUNDS:
            await self._end_game()
        else:
            self.current_q = self.next_q or await generate_question()
            await self._start_round()

    async def _end_game(self):
        winner = max(self.players.values(), key=lambda p: p["score"])
        await self.sio.emit("game_over", {
            "winner":      winner["name"],
            "finalScores": {p["name"]: p["score"] for p in self.players.values()},
        }, to=self.room_code)

    # ------------------------------------------------------------------
    # Real-time updates from clients
    # ------------------------------------------------------------------

    def update_position(self, sid: str, data: dict):
        p = self.players.get(sid)
        if p:
            p["x"]      = data.get("x",      p["x"])
            p["y"]      = data.get("y",      p["y"])
            p["facing"] = data.get("facing", p["facing"])

    async def handle_attack(self, sid: str, data: dict):
        attacker = self.players.get(sid)
        if not attacker:
            return
        facing = data.get("facing", 1)

        for victim_sid, victim in self.players.items():
            if victim_sid == sid:
                continue
            dx = abs(attacker["x"] - victim["x"])
            dy = abs(attacker["y"] - victim["y"])
            if dx < 90 and dy < 70:
                await self.sio.emit("apply_knockback", {"direction": facing}, to=victim_sid)

    async def award_point(self, sid: str):
        """Client calls this when it detects it is standing on the correct platform at round end."""
        p = self.players.get(sid)
        if p:
            p["score"] += 1

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------

    def _players_list(self):
        return [{"id": sid, **p} for sid, p in self.players.items()]
