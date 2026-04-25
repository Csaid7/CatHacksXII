"""
AnswerRush — one-command startup.
Run from the project root:  python inject.py

1. Injects the Socket.io bridge into godot/export/index.html (safe to re-run)
2. Starts the uvicorn server on port 3000
"""

import os
import subprocess
import sys

# ── Step 1: Inject Socket.io ──────────────────────────────────────────────────

INDEX = "godot/export/index.html"

INJECTION = """
\t\t<!-- AnswerRush: Socket.io bridge — must be injected after the Godot script -->
\t\t<script src="https://cdn.socket.io/4.7.5/socket.io.min.js"></script>
\t\t<script>
\t\t\tvar socket = io("http://localhost:3000", { transports: ["websocket"] });
\t\t\tsocket.on("connect", function () {
\t\t\t\tconsole.log("[socket] connected, id =", socket.id);
\t\t\t});
\t\t\tsocket.on("connect_error", function (err) {
\t\t\t\tconsole.error("[socket] connection error:", err.message);
\t\t\t});
\t\t</script>"""

if not os.path.exists(INDEX):
    print(f"ERROR: {INDEX} not found — export the Godot project to godot/export/ first.")
    sys.exit(1)

with open(INDEX, "r", encoding="utf-8") as f:
    html = f.read()

if "socket.io" in html:
    print("Socket.io already injected — skipping.")
else:
    html = html.replace("</body>", INJECTION + "\n\t</body>")
    with open(INDEX, "w", encoding="utf-8") as f:
        f.write(html)
    print("Socket.io injected successfully.")

# ── Step 2: Start the server ──────────────────────────────────────────────────

print("\nStarting server at http://localhost:3000 ...\n")

subprocess.run(
    [sys.executable, "-m", "uvicorn", "index:socket_app", "--host", "0.0.0.0", "--port", "3000", "--reload"],
    cwd=os.path.join(os.path.dirname(os.path.abspath(__file__)), "server"),
)
