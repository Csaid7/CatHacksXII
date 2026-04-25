# AnswerRush 🎮
### CatHacksXII — 24-Hour Hackathon Project

A real-time multiplayer quiz brawler. Race to the correct answer platform and fight your opponents off it before the timer runs out.

---

## How to Play

1. Open the game in your browser
2. Enter a room code and your name
3. Share the room code with up to 3 friends
4. A trivia question appears — jump to the platform with your answer
5. Punch opponents off the correct platform to steal their point
6. Whoever is on the correct platform when the timer hits 0 scores
7. Most points after 15 rounds wins

**Controls:** `← →` Move &nbsp;|&nbsp; `Space` Jump &nbsp;|&nbsp; `X` Punch

---

## Tech Stack

- **Game:** Godot 4 → exported to HTML5
- **Backend:** Python + FastAPI + Socket.io
- **Multiplayer:** WebSocket (Socket.io protocol)
- **Questions:** Claude AI — 76 pre-generated trivia questions across 8 categories

---

## Run Locally

**Start the server:**
```bash
cd server
pip install -r requirements.txt
uvicorn index:socket_app --host 0.0.0.0 --port 3000 --reload
```

Open `http://localhost:3000` in up to 4 browser tabs. Use the same room code in each tab.

---

## Team

| | Role |
|---|---|
| Caleb | AI questions, server logic, networking |
| Kiara | Godot game engine, physics, animations |
| Nate | Godot networking, lobby, integration |
| Gunner | Backend, Socket.io, round management |

---

*Built in 24 hours at CatHacksXII — 2026*
