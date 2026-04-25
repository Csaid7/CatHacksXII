# Godot Input Map Setup

Open **Project → Project Settings → Input Map** and add these actions:

| Action name  | Key                  |
|--------------|----------------------|
| `move_left`  | A  (or Left arrow)   |
| `move_right` | D  (or Right arrow)  |
| `jump`       | W  (or Space / Up)   |
| `fast_fall`  | S  (or Down arrow)   |
| `attack`     | Shift  (or Z / X)    |

These match the names used in Player.gd.
Since this is a browser game each player has their own tab, so there's no
need for multi-key layouts — everyone uses the same key names.
