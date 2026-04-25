# AnswerRush — Team Architecture Guide
### CatHacksXII | 24-Hour Build

---

# START HERE — What Each Person Does RIGHT NOW

---

## Person 1 — Godot Game Dev

**Step 1 — Install Godot 4**
Go to [godotengine.org](https://godotengine.org/download) → download **Godot 4 (Standard, not Mono)** → open it.

**Step 2 — Create the project**
New Project → name it `answerrush` → save it inside the repo at `godot/` → 2D renderer.

**Step 3 — Build this exact thing first**
Create `scenes/Game.tscn`. Add:
- A `StaticBody2D` with a long flat `CollisionShape2D` as the ground line
- A `CharacterBody2D` (your player) with a `CollisionShape2D` (capsule) and a `ColorRect` so you can see it
- Attach `Player.gd` to it

Your `Player.gd` starting point:
```gdscript
extends CharacterBody2D

const SPEED = 280.0
const JUMP_VELOCITY = -650.0
const GRAVITY = 2000.0

func _physics_process(delta):
    velocity.y += GRAVITY * delta
    if Input.is_action_just_pressed("ui_accept") and is_on_floor():
        velocity.y = JUMP_VELOCITY
    var dir = Input.get_axis("ui_left", "ui_right")
    velocity.x = dir * SPEED
    move_and_slide()
```

Hit F5. Player should walk and jump. That's your first checkpoint.

**Step 4 — Add platforms**
Create `scenes/Platform.tscn` — a `StaticBody2D` + `CollisionShape2D` (rectangle) + `Label`. Set one-way collision on so players can jump up through them.

Place 4 platforms at different heights in `Game.tscn`.

**Resources**
- GDScript basics: [docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_basics.html](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_basics.html)
- CharacterBody2D guide: [docs.godotengine.org/en/stable/tutorials/physics/using_character_body_2d.html](https://docs.godotengine.org/en/stable/tutorials/physics/using_character_body_2d.html)
- YouTube: search **"Godot 4 platformer tutorial"** — any 2024 video works

---

## Person 2 — Godot Networking

**You share the Godot project with Person 1. Clone the same repo.**

**Step 1 — Install Godot 4** (same as Person 1)

**Step 2 — Spike the JS bridge IMMEDIATELY**
This is the riskiest part of the whole project. Do this before anything else.

Create a standalone test — `scenes/NetTest.tscn` with a single Node and this script:
```gdscript
extends Node

func _ready():
    if OS.get_name() == "Web":
        JavaScriptBridge.eval("""
            window._socket.emit('hello', { msg: 'Godot connected!' });
        """)
```

Export the project to HTML5 (Project → Export → HTML5 → Export Project → save to `godot/export/`).

In the exported `index.html`, add this BEFORE the Godot engine script tag:
```html
<script src="https://cdn.socket.io/4.7.4/socket.io.min.js"></script>
<script>
  window._socket = io('http://localhost:3000');
  window._socket.on('connect', () => {
      console.log('Socket connected:', window._socket.id);
  });
</script>
```

Open in a browser, check the console. If you see "Socket connected" — the spike worked, everything is unblocked.

**Step 3 — Build NetworkManager.gd**
Once the spike works, turn it into a proper Autoload singleton (the code is in the role section below).

**Step 4 — Sync positions**
Once Person 1 has the player moving and Person 3 has the server running, your job is making Player 1's movement appear on Player 2's screen.

**Resources**
- JavaScriptBridge docs: [docs.godotengine.org/en/stable/classes/class_javascriptbridge.html](https://docs.godotengine.org/en/stable/classes/class_javascriptbridge.html)
- Godot HTML5 export: [docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html)
- Socket.io client docs: [socket.io/docs/v4/client-api](https://socket.io/docs/v4/client-api/)

---

## Person 3 — Backend

**Pick Python or Node right now. Don't switch halfway.**

### If Python

```bash
mkdir server && cd server
pip install fastapi uvicorn python-socketio anthropic
```

Create `server/index.py`:
```python
import socketio
import uvicorn
from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles

sio = socketio.AsyncServer(async_mode='asgi', cors_allowed_origins='*')
app = FastAPI()
socket_app = socketio.ASGIApp(sio, app)

rooms = {}

@sio.event
async def connect(sid, environ):
    print(f"connected: {sid}")

@sio.event
async def disconnect(sid):
    print(f"disconnected: {sid}")

@sio.event
async def join_room(sid, data):
    code = data['roomCode']
    await sio.enter_room(sid, code)
    if code not in rooms:
        rooms[code] = []
    rooms[code].append(sid)
    print(f"{sid} joined room {code}")
    if len(rooms[code]) == 2:
        await sio.emit('room_ready', {'players': rooms[code]}, room=code)

@sio.event
async def player_move(sid, data):
    # find this player's room and broadcast to the other player
    pass

if __name__ == "__main__":
    uvicorn.run("index:socket_app", host="0.0.0.0", port=3000, reload=True)
```

Run it: `python index.py`

### If Node

```bash
mkdir server && cd server
npm init -y
npm install express socket.io
```

Create `server/index.js`:
```js
const express = require('express');
const { createServer } = require('http');
const { Server } = require('socket.io');

const app = express();
const httpServer = createServer(app);
const io = new Server(httpServer, { cors: { origin: '*' } });
const rooms = {};

io.on('connection', (socket) => {
    console.log('connected:', socket.id);

    socket.on('join_room', ({ roomCode }) => {
        socket.join(roomCode);
        if (!rooms[roomCode]) rooms[roomCode] = [];
        rooms[roomCode].push(socket.id);
        console.log(`${socket.id} joined ${roomCode}`);
        if (rooms[roomCode].length === 2) {
            io.to(roomCode).emit('room_ready', { players: rooms[roomCode] });
        }
    });

    socket.on('player_move', (data) => {
        // find room and broadcast
    });
});

httpServer.listen(3000, () => console.log('Server on :3000'));
```

Run it: `node index.js`

**Your first checkpoint:** Two browser tabs connect, server logs both connections, server logs "room_ready" when both join the same code.

**Resources**
- python-socketio: [python-socketio.readthedocs.io](https://python-socketio.readthedocs.io)
- Socket.io (Node): [socket.io/docs/v4](https://socket.io/docs/v4/)

---

## Person 4 — AI + Questions

**Step 1 — Get your API key**
Go to [console.anthropic.com](https://console.anthropic.com) → create an account → API Keys → create key.

Set it in your terminal:
```bash
export ANTHROPIC_API_KEY=sk-ant-...   # Mac/Linux
set ANTHROPIC_API_KEY=sk-ant-...      # Windows
```

**Step 2 — Test question generation standalone**

Python:
```bash
pip install anthropic
```
```python
# test_questions.py
import anthropic, json

client = anthropic.Anthropic()

msg = client.messages.create(
    model="claude-haiku-4-5-20251001",
    max_tokens=4000,
    messages=[{
        "role": "user",
        "content": """Generate 20 trivia questions across these categories:
                     Science, History, Geography, Pop Culture.
                     5 per category. Wrong answers must be plausible — players should genuinely disagree.
                     Return ONLY a JSON array, no extra text:
                     [{"category":"...","question":"...","platforms":[
                       {"id":"A","label":"...","isCorrect":true},
                       {"id":"B","label":"...","isCorrect":false},
                       {"id":"C","label":"...","isCorrect":false},
                       {"id":"D","label":"...","isCorrect":false}
                     ]},...]"""
    }]
)

questions = json.loads(msg.content[0].text)
print(f"Generated {len(questions)} questions")

# Save to file as backup
with open("questions.json", "w") as f:
    json.dump(questions, f, indent=2)
```

Run: `python test_questions.py`

If it outputs a JSON file with 20 questions — you're done with step 2.

**Step 3 — Scale up to 80 questions**
Change the prompt to 80 questions across 8 categories. This is your question bank. Save it as `server/questions.json`. The server loads it on startup and picks randomly each round. No more API calls during gameplay.

**Step 4 — While that's running, work on the HTML wrapper**
The Godot HTML5 export gives you a basic `index.html`. Style it — add a title, a background color, maybe instructions. This is what judges see first.

**Resources**
- Anthropic Python SDK: [docs.anthropic.com](https://docs.anthropic.com)
- Free trivia backup dataset: search "opentdb API" (Open Trivia Database) — free JSON trivia if Claude is down

---

## Coordination Rules (Read These Now)

1. **Person 1 owns all `.tscn` files.** Everyone else only edits `.gd` scripts. This prevents git merge conflicts on binary files.
2. **Person 2 and Person 3 agree on the event schema before either writes networking code.** The table in this doc is your contract.
3. **Person 4 generates the question bank early** and commits `questions.json` to the repo so Person 3 can use it immediately without waiting for API calls.
4. **Test on two browser tabs constantly**, not just in Godot's editor. Networking bugs only show up in the real export.
5. **One git branch each.** Merge to main only when something works end-to-end.

---

---

## What We're Building

A 2D multiplayer quiz brawler. Two players spawn on a ground line and jump up to floating platforms — each platform has a possible answer to a question. You have 15 seconds to get on the platform you think is correct and hold it. The twist: you can punch and push your opponent off their platform, Stick Fight style. Whoever is standing on the correct platform when the timer hits zero scores a point.

**Stack:** Godot 4 (exported to HTML5) + Node.js/Express/Socket.io backend (or Python/FastAPI — see below) + Claude API for questions.

---

## How It Looks

```
Question: "What is the capital of France?"

  [A: London]              [B: Tokyo]          ← high platforms
        [C: Paris]     [D: Berlin]              ← mid platforms

═══════════════════════════════════════════     ← spawn line
                   [P1][P2]
```

- Players spawn on the ground line together
- Jump up to platforms at different heights
- Platforms have the answer written on them
- Fight/push each other off
- Timer hits 0 → whoever is on the correct platform wins the round

---

## Full System Architecture

```
┌─────────────────────────────────────────────────────┐
│               BROWSER (Player 1)                    │
│                                                     │
│   Godot 4 HTML5 Export (.wasm + .html)              │
│   └── GDScript game logic                           │
│   └── JavaScriptBridge → socket.io.js client        │
└────────────────────┬────────────────────────────────┘
                     │  WebSocket (Socket.io protocol)
                     │
┌────────────────────▼────────────────────────────────┐
│              NODE.JS SERVER                         │
│                                                     │
│   Express.js  →  serves the HTML5 game files        │
│   Socket.io   →  handles all multiplayer events     │
│   Game Logic  →  timer, scoring, round management   │
│   Claude API  →  generates questions each round     │
└─────────────────────────────────────────────────────┘
                     │  WebSocket (Socket.io protocol)
                     │
┌────────────────────▼────────────────────────────────┐
│               BROWSER (Player 2)                    │
│   (same as Player 1)                                │
└─────────────────────────────────────────────────────┘
```

---

## Python vs Node — Backend Choice

**The backend can be written in Python instead of Node.js.** The game (Godot) doesn't care — the Socket.io protocol is the same either way.

| | Node.js | Python |
|---|---|---|
| Framework | Express + Socket.io | FastAPI + python-socketio |
| Claude SDK | `@anthropic-ai/sdk` | `anthropic` (this is the primary SDK — cleaner) |
| Install | `npm install` | `pip install fastapi uvicorn python-socketio anthropic` |
| Run | `node index.js` | `uvicorn index:app` |
| Pick if... | your team knows JS | your team knows Python better |

**GDScript (Godot's language) is not Python** — it just looks like it. Same indentation style, same `for`/`if`/`while`, same list/dict syntax, just `func` instead of `def`. Anyone who knows Python can write GDScript within 30 minutes. There is no Python path for the game itself — Pygame cannot export to HTML5 reliably enough for a hackathon.

**Python backend entry point (FastAPI + python-socketio):**
```python
# server/index.py
import socketio
from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles

sio = socketio.AsyncServer(async_mode='asgi', cors_allowed_origins='*')
app = FastAPI()
socket_app = socketio.ASGIApp(sio, app)

app.mount("/game", StaticFiles(directory="../godot/export", html=True), name="game")

rooms = {}  # roomCode → GameRoom

@sio.event
async def connect(sid, environ):
    print(f"Player connected: {sid}")

@sio.event
async def join_room(sid, data):
    room_code = data['roomCode']
    await sio.enter_room(sid, room_code)
    # add to rooms dict, start game when 2 players join

@sio.event
async def player_move(sid, data):
    # update position snapshot, server will broadcast it
    pass

@sio.event
async def player_attack(sid, data):
    # validate range, emit apply_knockback to victim if valid
    pass
```

**Python question generation (questionGen.py):**
```python
import anthropic
import json

client = anthropic.Anthropic()  # reads ANTHROPIC_API_KEY from env

async def generate_question(topic: str = None):
    topic_line = f"Topic: {topic}." if topic else "Pick a random fun topic."
    msg = client.messages.create(
        model="claude-haiku-4-5-20251001",  # fast + cheap
        max_tokens=300,
        messages=[{
            "role": "user",
            "content": f"""Generate a trivia question with exactly 4 answer choices.
                          {topic_line}
                          Rules: wrong answers must be PLAUSIBLE (players should genuinely debate).
                          Return ONLY valid JSON, no extra text:
                          {{
                            "question": "...",
                            "platforms": [
                              {{"id": "A", "label": "...", "isCorrect": true}},
                              {{"id": "B", "label": "...", "isCorrect": false}},
                              {{"id": "C", "label": "...", "isCorrect": false}},
                              {{"id": "D", "label": "...", "isCorrect": false}}
                            ]
                          }}"""
        }]
    )
    return json.loads(msg.content[0].text)
```

**If using Python, the folder structure changes slightly:**
```
server/
├── index.py          ← FastAPI + python-socketio (replaces index.js)
├── game_room.py      ← Room state class (replaces GameRoom.js)
├── question_gen.py   ← Claude API (replaces questionGen.js)
└── requirements.txt  ← fastapi uvicorn python-socketio anthropic
```

Everything else in this guide (Godot code, events, critical path, roles) stays exactly the same.

---

## Critical Technical Note: Godot + Socket.io

Godot's built-in WebSocket speaks raw WS. Socket.io uses its own protocol on top.
Since we export to HTML5, we can call JavaScript directly from GDScript.
That means we load the Socket.io JS client in the HTML page and talk to it from Godot.

```gdscript
# NetworkManager.gd — how Godot talks to Socket.io
var socket = JavaScriptBridge.eval("io('http://localhost:3000')", true)
JavaScriptBridge.eval("""
    socket.on('state_update', function(data) {
        window._latestState = JSON.stringify(data);
    });
""")
```

This is the glue that makes everything work. **Person 2 must spike this on hour 1.**

---

## Game Events (What the Server and Client Say to Each Other)

| Event | Who Sends It | What's In It |
|---|---|---|
| `join_room` | Client → Server | `{ roomCode, playerName }` |
| `room_ready` | Server → Both | `{ players[], yourId }` |
| `round_start` | Server → Both | `{ question, platforms: [{id, label, isCorrect, x, y}] }` |
| `tick` | Server → Both | `{ timeLeft }` — sent every second |
| `player_move` | Client → Server | `{ x, y, vy, facing }` — sent ~20x/sec |
| `state_update` | Server → Both | `{ players: [{id, x, y, facing}] }` — sent ~20x/sec |
| `player_attack` | Client → Server | `{ facing }` |
| `apply_knockback` | Server → Target | `{ direction }` — only if punch landed |
| `round_result` | Server → Both | `{ winnerId, correctPlatformId, scores }` |
| `game_over` | Server → Both | `{ winner, finalScores }` |

---

## Folder Structure

```
answerrush/
│
├── server/                     ← Person 3 + 4
│   ├── index.js                ← Express + Socket.io entry point
│   ├── GameRoom.js             ← Room state, timer, round logic
│   ├── questionGen.js          ← Claude API calls
│   └── package.json
│
└── godot/                      ← Person 1 + 2
    ├── project.godot
    ├── scenes/
    │   ├── Game.tscn           ← Main scene, holds everything
    │   ├── Player.tscn         ← CharacterBody2D player
    │   ├── Platform.tscn       ← StaticBody2D + answer label
    │   └── Lobby.tscn          ← Room code entry screen
    ├── scripts/
    │   ├── Player.gd           ← Movement, jump, attack, stun
    │   ├── NetworkManager.gd   ← Autoload singleton, JS bridge
    │   ├── GameManager.gd      ← Spawns platforms, runs HUD
    │   └── Platform.gd         ← Tracks who is standing on it
    └── export/                 ← HTML5 build output (served by Node)
```

---

## The Stick Fight Physics Feel

This is what makes the game fun. Tune these numbers first, everything else second.

| Setting | Value | Why |
|---|---|---|
| Gravity | 2000 (double Godot default) | Heavy, punchy falls |
| Jump velocity | -650 | Snappy, not floaty |
| Walk speed | 280 | Fast enough to feel urgent |
| Knockback on hit | `Vector2(±750, -250)` | Sends them flying |
| Stun duration | 0.4 seconds | Can't counter-spam |
| Attack range | 90px horizontal, 70px vertical | Generous so it feels responsive |

---

---

# ROLE BREAKDOWN

---

## Person 1 — Godot Game Dev (Physics & Gameplay)

**You own:** Everything that makes the game feel good to play.

### What You Build

**Player.tscn + Player.gd**
- `CharacterBody2D` with collision shape
- Walk left/right (arrow keys or WASD)
- Jump (Space or W) — single jump only, no double jump
- Fast fall (hold S/down) — important for getting back down fast
- Punch/push attack (one button, e.g. Z or Shift)
- Stun state — when hit, can't move or attack for 0.4s
- Facing direction tracked (for knockback direction)

```gdscript
# Core movement loop in Player.gd
func _physics_process(delta):
    velocity.y += GRAVITY * delta
    if Input.is_action_just_pressed("jump") and is_on_floor():
        velocity.y = JUMP_VELOCITY
    var dir = Input.get_axis("move_left", "move_right")
    velocity.x = dir * SPEED
    move_and_slide()
```

**Platform.tscn + Platform.gd**
- `StaticBody2D` with a `CollisionShape2D` (rectangle)
- `Label` node on top showing the answer text
- One-way collision (can jump up through from below)
- Area2D to detect which player is currently standing on it

**Game.tscn**
- Holds the ground line, platforms, both players
- Camera that shows the whole level

### What You Need to Learn
- GDScript syntax (very similar to Python)
- `CharacterBody2D` and `move_and_slide()` — [Godot docs](https://docs.godotengine.org/en/stable/tutorials/physics/using_character_body_2d.html)
- One-way collision platforms in Godot
- Signals (how nodes talk to each other)

### Your Day 1 Goal
Single player, local: character walks, jumps, punches, gets knocked back, platforms exist with labels. No networking yet.

---

## Person 2 — Godot Networking (JS Bridge & Sync)

**You own:** Everything that connects Godot to the server. This is the hardest role technically — start immediately.

### What You Build

**NetworkManager.gd (Autoload Singleton)**
This is a single script that runs globally and all other scripts can call.

```gdscript
extends Node

var socket  # JavaScript Socket.io object
var my_id: String = ""

func _ready():
    if OS.get_name() == "Web":
        socket = JavaScriptBridge.eval("window._socket", true)

func emit(event: String, data: Dictionary):
    var json = JSON.stringify(data)
    JavaScriptBridge.eval("window._socket.emit('%s', %s)" % [event, json])

func send_position(pos: Vector2, vel_y: float, facing: int):
    emit("player_move", {
        "x": pos.x, "y": pos.y,
        "vy": vel_y, "facing": facing
    })
```

**index.html (modified export)**
After Godot HTML5 export, edit the generated `index.html` to add Socket.io:
```html
<script src="https://cdn.socket.io/4.7.4/socket.io.min.js"></script>
<script>
  window._socket = io('http://localhost:3000');
  window._socket.on('connect', () => console.log('connected:', window._socket.id));
</script>
```

**What you receive from server and apply:**
- `round_start` → tell GameManager to spawn platforms with correct labels
- `state_update` → move the remote player node to their position (lerp it for smoothness)
- `apply_knockback` → call `receive_knockback(direction)` on local Player
- `tick` → update the timer label in HUD
- `round_result` → show who won the round, update score display

**HUD scene**
- Question text (Label at top)
- Timer bar (ProgressBar or Label)
- Score display (P1: 0 | P2: 0)

### What You Need to Learn
- Godot Autoloads (singletons)
- `JavaScriptBridge` — Godot's HTML5-only JS interop
- How to parse JSON in GDScript: `JSON.parse_string(str)`
- Linear interpolation: `lerp(current, target, 0.15)` for smooth remote player movement
- Godot HTML5 export process

### Your Day 1 Goal
Two browser tabs open. Move in one tab, see it reflected in the other. Just positions — no game logic yet.

---

## Person 3 — Backend (Node.js or Python — your choice)

**You own:** The server. You are the source of truth for everything game-state related.

### What You Build

**index.js — server entry point**
```js
const express = require('express');
const { createServer } = require('http');
const { Server } = require('socket.io');

const app = express();
const httpServer = createServer(app);
const io = new Server(httpServer, { cors: { origin: '*' } });

// Serve the Godot HTML5 export
app.use(express.static('../godot/export'));

const rooms = new Map(); // roomCode → GameRoom

io.on('connection', (socket) => {
    socket.on('join_room', ({ roomCode, playerName }) => {
        // add player to room, start game when 2 players join
    });
    socket.on('player_move', (data) => {
        // update this player's position in room state
    });
    socket.on('player_attack', (data) => {
        // validate range, emit apply_knockback to victim if valid
    });
});

httpServer.listen(3000);
```

**GameRoom.js — one instance per active match**
```js
class GameRoom {
    constructor(io, roomCode) {
        this.io = io;
        this.roomCode = roomCode;
        this.players = {};   // socketId → { x, y, facing }
        this.scores = {};    // socketId → number
        this.timeLeft = 15;
        this.currentAnswer = null; // correct platform id
    }

    startRound(question) {
        this.timeLeft = 15;
        this.io.to(this.roomCode).emit('round_start', question);
        this.timer = setInterval(() => {
            this.timeLeft--;
            this.io.to(this.roomCode).emit('tick', { timeLeft: this.timeLeft });
            if (this.timeLeft <= 0) this.endRound();
        }, 1000);
    }

    endRound() {
        clearInterval(this.timer);
        // check which player is on which platform
        // award point to player on correct platform
        // call questionGen for next round
    }

    broadcastState() {
        // called ~20x/sec via setInterval
        this.io.to(this.roomCode).emit('state_update', {
            players: Object.entries(this.players).map(([id, p]) => ({ id, ...p }))
        });
    }
}
```

**Attack validation (server is judge)**
```js
socket.on('player_attack', ({ facing }) => {
    const attacker = room.players[socket.id];
    const victimId = getOtherPlayer(socket.id, room);
    const victim = room.players[victimId];
    const dx = Math.abs(attacker.x - victim.x);
    const dy = Math.abs(attacker.y - victim.y);
    if (dx < 90 && dy < 70) {
        io.to(victimId).emit('apply_knockback', { direction: facing });
    }
});
```

### What You Need to Learn
**If Node:** Socket.io rooms/emit/on, Express static files, `setInterval` for the game loop
**If Python:** `python-socketio` async events, FastAPI static files, `asyncio` tasks for the timer loop
**Either way:** The event schema above is your contract — it doesn't change based on language

### Your Day 1 Goal
Server running on localhost:3000. Two clients can join the same room by code. Server echoes both players' positions back to each other. Timer loop works.

---

## Person 4 — AI Integration + Visual Polish

**You own:** Questions that make the game fun, and the visual layer that makes it look like a real game.

### What You Build

**Question generation — use whichever language matches Person 3's backend choice**

The code for both languages is in the "Python vs Node" section above. The key prompt is the same either way — your job is tuning it so wrong answers are genuinely tempting.

**Important:** Pre-generate the NEXT question while the current round plays — hides the API delay.

**Platform height assignment**
After getting the question from Claude, randomly assign which platform appears at which height so the correct answer isn't always in the same spot:
```python
# Python version
import random

def assign_platform_positions(platforms):
    positions = [
        {"x": 150, "y": -420}, {"x": 450, "y": -420},  # high
        {"x": 250, "y": -230}, {"x": 550, "y": -230},  # mid
    ]
    random.shuffle(positions)
    return [{**p, **pos} for p, pos in zip(platforms, positions)]
```
```js
// Node version
function assignPlatformPositions(platforms) {
    const positions = [
        { x: 150, y: -420 }, { x: 450, y: -420 },
        { x: 250, y: -230 }, { x: 550, y: -230 }
    ];
    positions.sort(() => Math.random() - 0.5);
    return platforms.map((p, i) => ({ ...p, ...positions[i] }));
}
```

**Visual polish tasks (if Claude question gen is done early)**
- Find or draw a stick figure sprite (free assets: itch.io, kenney.nl)
- Style the HTML wrapper (`index.html`) — dark background, title, instructions
- Add a lobby screen in Godot (room code input + join button)
- Sound effects: jump sound, punch sound, correct answer fanfare
- Deploy: server on [Render](https://render.com) (free), game files served from same server

### What You Need to Learn
- **If Python:** `pip install anthropic` — the Python SDK is Anthropic's primary one, very clean
- **If Node:** `npm install @anthropic-ai/sdk`
- How to set `ANTHROPIC_API_KEY` as an environment variable
- JSON parsing and error handling (LLMs sometimes return invalid JSON — always wrap in try/catch or try/except)
- Godot's `Label` node for displaying text
- Basic HTML/CSS for the wrapper page

### Your Day 1 Goal
`generateQuestion()` works and returns valid JSON. Server calls it and sends the result to clients. Labels appear on platforms in Godot.

---

# THE CRITICAL PATH

These things must happen in order. Everything else is parallel.

```
Hour 0-2: SPIKE — Person 2 gets Godot ↔ Socket.io working
          Two tabs, one message, confirm it appears in both.
          If this fails, nothing else matters.

Hour 2-4: FOUNDATION
          P1: Player walks and jumps locally
          P3: Server accepts 2 players in a room, echoes positions
          P2: Positions sync between tabs (can see remote player move)

Hour 4-8: CORE LOOP
          P1: Platforms exist, player can land on them
          P3: Timer runs, round_start fires, round_result fires
          P4: Claude generates question, platforms get labels
          P2: Platforms spawn from server data, question shows in HUD

Hour 8-16: GAME FEEL
          P1: Attack + knockback feels good (this takes iteration)
          P3: Attack validated server-side, knockback delivered
          P2: Knockback applied to local player correctly
          P4: Polish sprites, sound, HTML wrapper

Hour 16-24: INTEGRATE + FIX BUGS
          Full round plays end to end
          Scores work
          Game over screen
          Deploy
```

---

# DAY 1 AGREEMENTS (decide these NOW, before coding)

Write these down somewhere everyone can see:

1. **Server URL** — `http://localhost:3000` for dev, TBD for deploy
2. **Room join flow** — one player creates a room, shares a 4-letter code, other player types it in
3. **Win condition** — first to 5 points wins (or 3 for faster games)
4. **Platform IDs** — always `"A"`, `"B"`, `"C"`, `"D"`
5. **Player node names** — `Player1` and `Player2` in the scene tree
6. **Who owns Game.tscn** — Person 1. Everyone else edits only `.gd` scripts to avoid merge conflicts.

---

# QUICK REFERENCES

**Run the server (Node):**
```bash
cd server
npm install
node index.js
```

**Run the server (Python):**
```bash
cd server
pip install fastapi uvicorn python-socketio anthropic
uvicorn index:socket_app --reload --port 3000
```

**Export Godot to HTML5:**
Project → Export → Add HTML5 preset → Export Project → save to `godot/export/`

**Test locally:**
Open `http://localhost:3000` in two browser tabs

**Claude API key:**
```bash
export ANTHROPIC_API_KEY=sk-ant-...
```

**Useful Godot shortcuts:**
- F5 — run project
- F6 — run current scene
- Ctrl+Shift+O — search for a file

---

*Built at CatHacksXII — AnswerRush*
