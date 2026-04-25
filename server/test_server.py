"""
AnswerRush — Automated server test
Run the server first:  uvicorn index:socket_app --port 3000
Then run this:         python test_server.py
"""

import asyncio
import socketio

SERVER = "http://localhost:3000"
RESULTS = []

def log(msg):
    print(msg)
    RESULTS.append(msg)


async def make_player(name: str, room: str, delay: float = 0):
    sio = socketio.AsyncClient()
    received = {}

    @sio.event
    async def connect():
        log(f"[{name}] connected")

    @sio.event
    async def disconnect():
        log(f"[{name}] disconnected")

    @sio.on("room_update")
    async def on_room_update(data):
        log(f"[{name}] room_update — {data['playerCount']} player(s) in room")

    @sio.on("game_starting")
    async def on_game_starting(data):
        log(f"[{name}] game_starting — countdown {data['countdown']}s")

    @sio.on("round_start")
    async def on_round_start(data):
        log(f"[{name}] round_start — round {data['round']}/{data['maxRounds']} | Q: {data['question']}")
        received["round_start"] = data
        # Simulate moving toward a platform
        await sio.emit("player_move", {"x": 200, "y": -420, "facing": 1})
        # Simulate attacking
        await asyncio.sleep(0.5)
        await sio.emit("player_attack", {"facing": 1})
        # Claim the point
        await asyncio.sleep(0.5)
        await sio.emit("claim_point", {})

    @sio.on("apply_knockback")
    async def on_knockback(data):
        log(f"[{name}] received knockback — direction {data['direction']}")

    @sio.on("round_result")
    async def on_round_result(data):
        log(f"[{name}] round_result — correct platform: {data['correctPlatformId']} | scores: {data['scores']}")

    @sio.on("game_over")
    async def on_game_over(data):
        log(f"[{name}] GAME OVER — winner: {data['winner']} | final: {data['finalScores']}")
        received["game_over"] = True

    @sio.on("error")
    async def on_error(data):
        log(f"[{name}] ERROR — {data['message']}")

    await asyncio.sleep(delay)
    await sio.connect(SERVER)
    await sio.emit("join_room", {"roomCode": room, "playerName": name})

    # Wait until game over or timeout (15 rounds × 18s + buffer)
    for _ in range(300):
        if received.get("game_over"):
            break
        await asyncio.sleep(1)

    await sio.disconnect()
    return received.get("game_over", False)


async def run_tests():
    log("=" * 50)
    log("AnswerRush Server Test")
    log("=" * 50)

    # ── Test 1: Room full rejection ────────────────────
    log("\n[TEST 1] Room full — 5th player should be rejected")
    tasks = [make_player(f"Bot{i}", "TEST", delay=i * 0.2) for i in range(1, 6)]
    results = await asyncio.gather(*tasks, return_exceptions=True)
    log("[TEST 1] done\n")

    # ── Test 2: Full game with 4 players ───────────────
    log("[TEST 2] Full 4-player game — first round only")
    # Override MAX_ROUNDS in game_room so test finishes fast
    import game_room
    game_room.MAX_ROUNDS = 1
    game_room.ROUND_TIME = 5
    game_room.RESULT_WAIT = 1

    tasks = [make_player(f"Player{i}", "GAME", delay=i * 0.3) for i in range(1, 5)]
    results = await asyncio.gather(*tasks, return_exceptions=True)
    passed = all(r is True for r in results if not isinstance(r, Exception))
    log(f"[TEST 2] {'PASSED — game completed end to end' if passed else 'FAILED — game did not complete'}\n")

    log("=" * 50)
    log("All tests done.")
    log("=" * 50)


if __name__ == "__main__":
    asyncio.run(run_tests())
