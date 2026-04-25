import asyncio
import random

# Fixed platform positions — must match the block positions in Godot's main.tscn
# BlockA, B, C, D are placed at these exact coordinates in the scene
PLATFORM_POSITIONS = {
    "A": {"x": 102,  "y": 460},
    "B": {"x": 380,  "y": 322},
    "C": {"x": 712,  "y": 185},
    "D": {"x": 1020, "y": 328},
}

# One distinct color per player slot — sent to Godot and applied as a sprite tint
PLAYER_COLORS = ["ff4444", "4488ff", "44dd44", "ffcc00"]

# Spread players out on spawn so they don't stack on top of each other
PLAYER_STARTS = [
    {"x": 100, "y": 0},
    {"x": 250, "y": 0},
    {"x": 400, "y": 0},
    {"x": 550, "y": 0},
]

MAX_ROUNDS  = 15
ROUND_TIME  = 15   # seconds
RESULT_WAIT = 3    # pause between rounds so players can read the result


class GameRoom:
    def __init__(self, sio, room_code: str):
        self.sio          = sio
        self.room_code    = room_code
        self.players      = {}     # sid → {name, x, y, facing, score, number}
        self.round_num    = 0
        self.time_left    = ROUND_TIME
        self.current_q    = None
        self._timer       = None   # asyncio Task for the countdown
        self._broadcast   = None   # asyncio Task for the position stream
        self.round_active    = False
        self._scored         = set()   # sids that already claimed a point this round
        self._question_pool  = []      # shuffled pool — questions are popped in order so no repeats
        self._correct_pos    = None    # position of the correct platform this round {x, y}

    # ------------------------------------------------------------------
    # Lobby
    # ------------------------------------------------------------------

    async def add_player(self, sid: str, name: str):
        number = len(self.players) + 1
        start  = PLAYER_STARTS[number - 1]
        self.players[sid] = {
            "name":   name,
            "x":      start["x"],
            "y":      start["y"],
            "facing": 1,
            "score":  0,
            "number": number,
            "color":  PLAYER_COLORS[number - 1],  # unique color per slot
        }
        await self._broadcast_room_update(sid)
        # Fourth player joining fills the room — kick off the game automatically
        if len(self.players) == 3:
            asyncio.create_task(self.start_game())

    async def player_left(self, sid: str):
        self.players.pop(sid, None)
        # Cancel background tasks — without this they'd loop forever on a shrinking player list
        if self._timer:
            self._timer.cancel()
        if self._broadcast:
            self._broadcast.cancel()
        # Let remaining players know someone disconnected
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
        # Everyone needs the updated player list, but yourId is only meaningful to the new player.
        # Send to the whole room first (skipping new_sid), then send to new_sid with yourId included.
        await self.sio.emit("room_update", payload, room=self.room_code, skip_sid=new_sid)
        await self.sio.emit("room_update", {**payload, "yourId": new_sid}, to=new_sid)

    # ------------------------------------------------------------------
    # Game flow
    # ------------------------------------------------------------------

    def _next_question(self) -> dict:
        # refill and re-shuffle the pool when empty so the game never runs out
        if not self._question_pool:
            import question_gen
            question_gen._load_bank()           # fills question_gen._bank in place
            self._question_pool = question_gen._bank.copy()  # copy AFTER loading
            random.shuffle(self._question_pool)
            print(f"[Pool] Loaded {len(self._question_pool)} questions. First: {self._question_pool[-1]['question'][:40]}")
        q = self._question_pool.pop().copy()
        q["platforms"] = list(q["platforms"])
        random.shuffle(q["platforms"])
        q["correct"] = next(p["id"] for p in q["platforms"] if p["isCorrect"])
        return q

    async def start_game(self):
        countdown = 3
        await self.sio.emit("game_starting", {"countdown": countdown}, room=self.room_code)
        await asyncio.sleep(countdown)
        self.current_q = self._next_question()
        await self._start_round()

    async def _start_round(self):
        self.round_num  += 1
        self.time_left   = ROUND_TIME
        self._scored     = set()  # reset so everyone can score once in this round

        # Merge each platform with its fixed Godot scene position by ID
        platforms = [
            {**platform, **PLATFORM_POSITIONS[platform["id"]]}
            for platform in self.current_q["platforms"]
        ]

        # Store correct platform position for end-of-round check
        correct_id = self.current_q["correct"]
        self._correct_pos = PLATFORM_POSITIONS.get(correct_id)

        await self.sio.emit("round_start", {
            "round":     self.round_num,
            "maxRounds": MAX_ROUNDS,
            "question":  self.current_q["question"],
            "platforms": platforms,
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
            pass  # task was cancelled (e.g. player disconnected mid-round)

    async def _broadcast_loop(self):
        # Push all player positions to every client ~20 times per second
        try:
            while True:
                await self.sio.emit(
                    "state_update",
                    {"players": self._players_list()},
                    room=self.room_code,
                )
                await asyncio.sleep(1 / 60)
        except asyncio.CancelledError:
            pass

    async def _end_round(self):
        self._broadcast.cancel()
        self.round_active = False

        correct_id = self.current_q["correct"]

        # Award points to every player standing on the correct platform at timer end
        if self._correct_pos:
            cx = self._correct_pos["x"]
            cy = self._correct_pos["y"]
            print(f"[Round end] Correct platform pos: x={cx} y={cy}")
            for sid, player in self.players.items():
                dx = abs(player["x"] - cx)
                dy = abs(player["y"] - cy)
                print(f"  Player {player['name']}: x={player['x']:.0f} y={player['y']:.0f} | dx={dx:.0f} dy={dy:.0f}")
                if dx < 85 and dy < 80:
                    player["score"] += 1
                    print(f"  → POINT awarded to {player['name']}")

        await self.sio.emit("round_result", {
            "correctPlatformId": correct_id,
            "scores": {p["name"]: p["score"] for p in self.players.values()},
        }, room=self.room_code)

        await asyncio.sleep(RESULT_WAIT)

        if self.round_num >= MAX_ROUNDS:
            await self._end_game()
        else:
            self.current_q = self._next_question()
            await self._start_round()

    async def restart(self):
        # reset scores and start a fresh game in the same room with the same players
        for player in self.players.values():
            player["score"] = 0
        self.round_num       = 0
        self._question_pool  = []   # clear pool so it reshuffles
        asyncio.create_task(self.start_game())

    async def _end_game(self):
        # Highest score wins; if tied, the player who appears first in the dict wins
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
        # Fall back to the stored value if a field is missing from the packet
        player["x"]      = data.get("x",      player["x"])
        player["y"]      = data.get("y",      player["y"])
        player["facing"] = data.get("facing", player["facing"])

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
            # ATTACK_X=90, ATTACK_Y=70 — these must stay in sync with Player.gd constants
            if dx < 90 and dy < 70:
                await self.sio.emit("apply_knockback", {"direction": facing}, to=target_sid)

    async def award_point(self, sid: str):
        # Points are now awarded server-side at round end based on position
        # claim_point from clients is ignored — kept for API compatibility
        pass

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------

    def _players_list(self):
        # Flatten the players dict into a list with sid included as "id"
        return [
            {
                "id":     sid,
                "name":   p["name"],
                "x":      p["x"],
                "y":      p["y"],
                "facing": p["facing"],
                "score":  p["score"],
                "color":  p["color"],
            }
            for sid, p in self.players.items()
        ]
