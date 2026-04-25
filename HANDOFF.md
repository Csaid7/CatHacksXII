# AnswerRush — Claude Project Handoff
### CatHacksXII | 24-Hour Hackathon

---

## What We're Building

A 2D multiplayer quiz brawler. 4 players each open the game in their own browser tab.
A trivia question appears at the top. Four answer platforms (A / B / C / D) are scattered
around the level. Players fight each other off platforms Stick Fight-style. After 15 seconds,
anyone standing on the correct platform earns a point. First to the most points after 15 rounds wins.

**The game runs entirely in the browser.** No app install. Players join by going to a URL
and typing a 4-letter room code.

---

## Tech Stack

| Layer | Technology | Why |
|---|---|---|
| Game engine | Godot 4 → exported to HTML5 | 2D physics + browser delivery |
| Game scripting | GDScript (Python-like syntax) | Ships with Godot |
| Backend | Python + FastAPI + python-socketio | Real-time WebSocket server |
| AI questions | Anthropic Python SDK → Claude Haiku | Fast + cheap question generation |
| Deploy | Railway (free tier) | One-command Python deploy |

---

## Architecture

```
Browser (Player 1)                Browser (Player 2–4)
  Godot HTML5 export                same game, same URL
  GDScript game logic               each tab = one player
  JavaScriptBridge ──────┐   ┌───── JavaScriptBridge
                         ▼   ▼
                  Python Server (FastAPI + python-socketio)
                  ├── Lobby / room management
                  ├── 15-second round timer (authoritative)
                  ├── Position relay (~20×/sec)
                  ├── Attack validation + knockback dispatch
                  ├── Score tracking
                  └── Claude API → question generation
```

**Key design decision:** The server is authoritative. Clients send inputs up;
the server relays state back down. Nobody cheats by running their own physics.

**Godot ↔ Socket.io bridge:** Godot exports to HTML5, so GDScript can call
JavaScript directly via `JavaScriptBridge`. The Socket.io JS client runs in
the HTML page; GDScript polls JS global variables every frame to read events.

---

## Folder Structure

```
answerrush/
├── HANDOFF.md                      ← you are here
│
├── server/
│   ├── index.py                    ← FastAPI + Socket.io entry point  [Person 3]
│   ├── game_room.py                ← Room state, timer, scoring       [Person 3]
│   ├── question_gen.py             ← Claude API calls                 [Person 4]
│   └── requirements.txt
│
└── godot/
    ├── INPUT_MAP.md                ← Godot input action setup guide
    ├── scripts/
    │   ├── NetworkManager.gd       ← JS bridge + all socket events    [Person 2]
    │   ├── Player.gd               ← Movement, jump, attack, stun     [Person 1]
    │   ├── Platform.gd             ← Answer platform + occupancy      [Person 1]
    │   └── GameManager.gd          ← Round flow, HUD, spawning        [Person 4]
    └── export_template/
        └── socket_inject.html      ← Paste into Godot's index.html   [Person 2]
```

**Godot scene structure (Person 1 builds this in the editor):**
```
Game.tscn (root)
├── GameManager       ← GameManager.gd
├── Platforms         ← Node2D container
├── Players           ← Node2D container
└── HUD (CanvasLayer)
    ├── QuestionLabel
    ├── TimerLabel
    ├── RoundLabel
    └── ScoreContainer

Player.tscn
├── CharacterBody2D   ← Player.gd
├── CollisionShape2D
├── Sprite2D
└── Label             (name tag)

Platform.tscn
├── StaticBody2D      ← Platform.gd
├── CollisionShape2D  (one-way enabled)
├── Area2D + CollisionShape2D  (standing detection)
└── Label             (answer text)
```

---

## The 4 Roles

### Person 1 — Godot Gameplay
**Files:** `godot/scripts/Player.gd`, `godot/scripts/Platform.gd`, all `.tscn` scenes

Get one character walking, jumping, and punching locally before touching networking.
Tune the physics feel. Build the Player and Platform scenes in the Godot editor.
Never needs to think about servers or events — just make it fun.

**Day 1 goal:** Single player walks, jumps, punches, gets knocked back, platforms exist with labels.

---

### Person 2 — Godot Networking
**Files:** `godot/scripts/NetworkManager.gd`, `godot/export_template/socket_inject.html`

The hardest role technically. The entire first 2 hours is one goal: move in one
browser tab, see it reflected in another. Add `NetworkManager.gd` as an Autoload
(Project → Project Settings → Autoload, name it exactly `NetworkManager`).
After Godot exports to HTML5, paste `socket_inject.html` contents into the
generated `index.html` before `</body>`.

**Day 1 goal:** Two browser tabs open. Move in one, see it in the other.

---

### Person 3 — Python Backend
**Files:** `server/index.py`, `server/game_room.py`

Run the server, manage lobby rooms, relay positions, validate attacks server-side,
run the round timer. Never needs to touch Godot.

```bash
cd server
pip install -r requirements.txt
export ANTHROPIC_API_KEY=sk-ant-...
uvicorn index:socket_app --host 0.0.0.0 --port 3000 --reload
```

**Day 1 goal:** Two clients join the same room by code. Server runs full round loop.

---

### Person 4 — AI & Game Flow
**Files:** `server/question_gen.py`, `godot/scripts/GameManager.gd`

On the server side: make Claude questions generate reliably with genuinely tricky wrong answers.
On the Godot side: wire the round flow — question appears, platforms spawn with labels,
scores update, game over screen shows. This is the integration role.

**Day 1 goal:** `generate_question()` returns valid JSON. Labels appear on platforms in Godot.

---

## Socket Event Contract

**This table is law. Never rename an event or field without telling everyone.**

| Event | Direction | Payload |
|---|---|---|
| `join_room` | Client → Server | `{ roomCode, playerName }` |
| `room_update` | Server → All | `{ players[], yourId, playerCount }` |
| `game_starting` | Server → All | `{ countdown }` |
| `round_start` | Server → All | `{ round, maxRounds, question, platforms[] }` |
| `tick` | Server → All | `{ timeLeft }` — every second |
| `player_move` | Client → Server | `{ x, y, vy, facing }` — ~20×/sec |
| `state_update` | Server → All | `{ players: [{id, x, y, facing}] }` — ~20×/sec |
| `player_attack` | Client → Server | `{ facing }` |
| `apply_knockback` | Server → Target | `{ direction }` |
| `claim_point` | Client → Server | `{}` — fired when local player is on correct platform at round end |
| `round_result` | Server → All | `{ correctPlatformId, scores }` |
| `game_over` | Server → All | `{ winner, finalScores }` |

**Platform data shape inside `round_start`:**
```json
{
  "id": "A",
  "label": "Paris",
  "isCorrect": true,
  "x": 150,
  "y": -420
}
```

**Player data shape inside `state_update`:**
```json
{ "id": "abc123", "x": 320.5, "y": 410.0, "facing": 1, "name": "Nate", "score": 3 }
```

---

## Physics Constants (Player.gd)

Tune these, but agree as a team before changing — they affect how knockback
is validated on the server.

| Constant | Value | Notes |
|---|---|---|
| `GRAVITY` | `2000.0` | Double Godot default — feels punchy |
| `JUMP_VELOCITY` | `-650.0` | Snappy, not floaty |
| `SPEED` | `280.0` | Fast enough to feel urgent |
| `KNOCKBACK` | `Vector2(750, -250)` | Sends them flying |
| `STUN_DURATION` | `0.4` sec | Prevents counter-spam |
| `ATTACK_X` | `90 px` | Must match server validation |
| `ATTACK_Y` | `70 px` | Must match server validation |

Attack range values in `game_room.py` must match `ATTACK_X` / `ATTACK_Y` above.

---

## Shared Contract — Things Nobody Changes Without Telling Everyone

1. **Socket event names** — exact strings, no renaming
2. **Platform IDs** — always `"A"` `"B"` `"C"` `"D"` (uppercase, string)
3. **Player position fields** — always `x`, `y`, `facing` (never renamed)
4. **Autoload name** — `NetworkManager` (exact, capital N and M)
5. **Attack range** — `ATTACK_X = 90`, `ATTACK_Y = 70` (server mirrors these)
6. **`Game.tscn` is owned by Person 1** — everyone else edits only `.gd` scripts
7. **Server port** — `3000` locally, Railway URL in production

---

## Critical Path

```
Hour 0–2   SPIKE
           Person 2: Godot ↔ Socket.io in two browser tabs
           If this fails, nothing else matters — get help immediately

Hour 2–4   FOUNDATION
           P1: Player walks + jumps locally
           P3: Server accepts 4 players, echoes positions
           P2: Remote player visible + moving in both tabs

Hour 4–8   CORE LOOP
           P1: Platforms exist, player lands on them
           P3: Timer runs, round_start + round_result fire
           P4: Claude generates question, platforms get labels
           P2: Platforms spawn from server data, question in HUD

Hour 8–16  GAME FEEL
           P1: Attack + knockback (iterate until fun)
           P3: Attack validated server-side
           P4: Polish sprites, sound, HTML wrapper

Hour 16–24 SHIP IT
           Full round end-to-end
           Scores work, game over screen works
           Deploy to Railway
```

**Hard rules:**
- No new features after hour 16
- Person 2 spikes networking before anyone writes game features
- Merge to main every 4 hours — never wait until the end

---

## How to Run

**Backend:**
```bash
cd server
pip install -r requirements.txt
export ANTHROPIC_API_KEY=sk-ant-...
uvicorn index:socket_app --host 0.0.0.0 --port 3000 --reload
```

**Godot (dev):**
- Open the `godot/` folder in Godot 4
- Press F5 to run in the editor (no networking)
- For networking: Export → HTML5 → open `http://localhost:3000` in browser

**Godot HTML5 export:**
1. Project → Export → Add Preset → Web
2. Export Project → save to `godot/export/`
3. Open `godot/export/index.html`, paste `socket_inject.html` before `</body>`
4. Done — server serves these files at `/`

**Test locally:**
```
Open http://localhost:3000 in 4 browser tabs
Each tab = one player
```

**Deploy (Railway):**
1. Push `server/` to GitHub
2. New Railway project → Deploy from GitHub → select repo
3. Set env var: `ANTHROPIC_API_KEY=sk-ant-...`
4. Railway gives you a URL → update `SERVER_URL` in `socket_inject.html`

---

## How to Use Claude on This Project

When starting a Claude session, paste this whole file plus your role's starter
`.gd` or `.py` files as context. Then say:

> "I'm Person [X] — [role name]. My goal right now is [specific critical path item].
> Help me build it. Don't change any socket event names or the shared contract items."

If Claude suggests renaming a socket event, a platform ID, or any field in the
contract table — override it and keep the agreed name.

---

## Game Config (easy to tweak)

```python
# game_room.py
MAX_ROUNDS  = 15
ROUND_TIME  = 15   # seconds per round
RESULT_WAIT = 3    # pause between rounds
```

```gdscript
# Player.gd
const SPEED         := 280.0
const JUMP_VELOCITY := -650.0
const GRAVITY       := 2000.0
```

---

*AnswerRush — CatHacksXII*
