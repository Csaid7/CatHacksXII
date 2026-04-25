# AnswerRush — Session Handoff

## What this is
A 2D multiplayer quiz brawler built for CatHacksXII. Players jump between floating platforms labeled A/B/C/D to answer trivia questions, and can punch each other for knockback. Built in Godot 4.6 (exported to HTML5) + Python FastAPI + Socket.io.

## How to run
From the project root:
```
python inject.py
```
This injects the socket.io bridge into `godot/export/index.html` (if needed) then starts the uvicorn server on port 3000. For LAN/cross-machine play, use ngrok:
```
ngrok http 3000
```
Share the ngrok HTTPS URL — plain HTTP over LAN fails Godot's secure-context check.

**After every Godot export:** re-run `python inject.py` to re-inject the socket.io bridge (exports overwrite index.html).

---

## Project structure
```
CatHacksProject/
├── inject.py                  # one-command startup (inject + server)
├── server/
│   ├── index.py               # FastAPI + socket.io entry point
│   ├── game_room.py           # room state, round timer, scoring
│   ├── question_gen.py        # pulls from questions.json
│   └── questions.json         # pre-generated question bank (run question_gen.py to rebuild)
└── godot/
    ├── project.godot          # open THIS folder in Godot editor (not godot/CatHacksXII/)
    ├── main.tscn              # main scene
    ├── main.gd                # round flow, HUD, claim-point detection
    ├── Player.tscn / Player.gd
    ├── AnswerBlock.tscn / AnswerBlock.gd
    ├── Lobby.gd               # host/join UI (attached to CanvasLayer in main.tscn)
    ├── NetworkManager.gd      # autoload singleton — JS bridge + all socket signals
    ├── block.tscn             # plain terrain block (170x34, StaticBody2D)
    └── export/
        └── index.html         # Godot HTML5 export (gets overwritten on each export)
```

---

## Architecture

### Server -> Client events
| Server event | NetworkManager signal | Handler in |
|---|---|---|
| `room_update` | `room_updated(players, your_id, player_count)` | Lobby.gd + main.gd |
| `game_starting` | `game_starting(countdown)` | Lobby.gd + main.gd |
| `round_start` | `round_started(round, max_rounds, question, platforms)` | main.gd |
| `tick` | `tick(time_left)` | main.gd |
| `state_update` | `state_updated(players)` | main.gd |
| `apply_knockback` | `knockback_received(direction)` | Player.gd |
| `round_result` | `round_result_received(correct_id, scores)` | main.gd |
| `game_over` | `game_over_received(winner, final_scores)` | main.gd |

### Client -> Server events
| GDScript call | Server event | Purpose |
|---|---|---|
| `NetworkManager.join_room(code, name)` | `join_room` | enter lobby |
| `NetworkManager.send_move(x, y, vy, facing)` | `player_move` | position sync every physics frame |
| `NetworkManager.send_attack(facing)` | `player_attack` | hit detection |
| `NetworkManager.claim_point()` | `claim_point` | score a point |

### How socket.io works in Godot HTML5
NetworkManager.gd uses `JavaScriptBridge.eval()` to attach socket.io listeners that push events into `window._gdEvents`. `_process()` drains this queue every frame and fires GDScript signals. Only active when `OS.has_feature("web")` — silent in the editor.

---

## Key files — current state

### server/index.py
- FastAPI + python-socketio AsyncServer
- `CrossOriginIsolationMiddleware` adds COOP/COEP headers (needed for Godot on non-localhost HTTP)
- Mounts static files at `../godot/export`
- Tracks `rooms: dict[str, GameRoom]` and `player_rooms: dict[str, str]`

### server/game_room.py
- `add_player`: starts game when 2 players join — **change `== 2` to `== 4` for demo**
- `_broadcast_room_update`: sends `yourId` only to the new player, sends full player list to whole room
- `_start_round`: fires `round_start` with question + shuffled platform positions
- `_broadcast_loop`: sends `state_update` ~20x/sec
- `award_point`: one point per player per round, only while round is active
- `_players_list()`: returns `[{id, name, x, y, facing, score}]` — id is the socket sid

### server/question_gen.py
- `generate_question()` pulls a random question from `questions.json`
- Each question: `{question, platforms: [{id, label, isCorrect}], correct}`
- `isCorrect` field is what main.gd reads to know which platform to watch
- Rebuild bank: `python question_gen.py` (needs `ANTHROPIC_API_KEY` env var)

### godot/NetworkManager.gd
- Autoload registered as `NetworkManager` in project.godot
- Signals: `room_updated`, `game_starting`, `round_started`, `tick`, `state_updated`, `knockback_received`, `round_result_received`, `game_over_received`
- Outbound: `join_room()`, `send_move()`, `send_attack()`, `claim_point()`

### godot/main.gd
- `_on_room_updated`: maps players array (join order) to Player1-4 nodes by index, sets `is_local`, stores `local_player` reference
- CRITICAL guard: `if your_id != "":` before setting `my_id` — server omits yourId on subsequent room updates
- `_on_round_started`: sets `correct_platform_id` from `platform.get("isCorrect")`, resets `_claimed` flag
- `_process`: every frame checks if local player is within 90px X / 80px Y of the correct block and is_on_floor() -> sends `claim_point()`, guarded by `_claimed` bool
- HUD built programmatically in `_build_hud()`: timer top-right (red at <=5s), scores top-left, result message center
- `_on_round_result`: flashes correct block green, wrong blocks red, updates score label
- `_on_game_over`: shows winner + leaderboard in questionText

### godot/Player.gd
- `is_local: bool` uses a property setter that calls `_show()` — visibility and collision restore instantly on assignment
- `_ready()`: hides self, zeroes `collision_layer` and `collision_mask` — unassigned slots are fully inert (invisible + no hitbox)
- All input hardcoded to slot "1" (left1/right1/jump1/attack1 = arrow keys, space, X) — every player uses same controls on their own screen
- `apply_remote_state(x, y, facing)`: called by main.gd from state_update; plays run if dx>2 else idle; reveals self on first call
- `_on_knockback(direction)`: `velocity = Vector2(direction * 1500, -250)`

### godot/Lobby.gd (attached to CanvasLayer in main.tscn)
- Host: generates 4-letter code (no I/O), shows it, calls join_room, hides panel+bg_rect so game world shows behind
- Join: validates 4-char code, calls join_room, shows WaitingPanel
- CRITICAL guard: `if your_id != "":` before `get_parent().my_id = your_id` — without this, subsequent room_updates (without yourId) wipe my_id and break all player assignment
- `_on_game_starting`: hides all UI including self

### godot/AnswerBlock.gd
- `set_answer(text)`: updates label
- `flash_correct()`: green -> white tween over 2.5s
- `flash_wrong()`: red -> white tween over 2.5s
- `reset_highlight()`: snap to white (called at each round start)

### inject.py
- Injects socket.io using `window.location.origin` (not hardcoded localhost — works on any network)
- Then starts uvicorn with --reload

---

## Scene structure (main.tscn)
```
Main (Node) — main.gd
  Player1 (CharacterBody2D) — Player.gd, playerNum=1
  Player2 (CharacterBody2D) — Player.gd, playerNum=2
  Player3 (CharacterBody2D) — Player.gd, playerNum=3
  Player4 (CharacterBody2D) — Player.gd, playerNum=4
  BlockA-D (Node2D) — AnswerBlock.gd, answer platforms
  QuestionBox — Label child used as questionText
  Timer
  Block-Block9 — plain terrain floor blocks
  CanvasLayer — Lobby.gd
    ColorRect (full-screen dark bg)
    Panel (lobby form: name input, host/join buttons)
      VBox
        NameInput
        ErrorLabel
        MainMenu (HostButton, JoinButton)
        HostMenu (GeneratedCode label, StartButton, BackButton)
        JoinMenu (CodeInput, JoinButton, BackButton)
    WaitingPanel (full-screen, shown to joiners while waiting)
      Label
    HostHUD (small corner panel, shown to host while in-game waiting)
      Label
```

---

## Bugs fixed (important context)
1. `my_id` overwritten with "" on subsequent room_updates — fixed by `if your_id != ""` guard in BOTH Lobby.gd AND main.gd (Lobby fires first as child node)
2. All players used wrong input slot — fixed by hardcoding "1" in Player.gd (each player uses slot-1 controls on their own screen)
3. Remote players sliding without animation — fixed by `apply_remote_state()` with dx-based run/idle logic
4. Unassigned player nodes blocking movement — fixed by zeroing collision_layer/mask in _ready()
5. Socket connecting to localhost on other machines — fixed with `window.location.origin`
6. Godot secure-context error on LAN — COOP/COEP headers added; use ngrok for cross-machine

## Things left to do
- Change player count threshold from 2 back to 4 in game_room.py before demo
- Polish: platform colors/labels in Godot editor (A=green, B=blue, C=orange, D=purple)
- Consider adding a respawn/reset position when round ends so players don't stay on platforms
- No reconnect handling — disconnecting mid-game leaves a frozen ghost
