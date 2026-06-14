# Phase 6 — Polish

Ship-blocking items only. Six task areas in dependency order; each has explicit
acceptance criteria. Phases within a task area must be done in the order listed.

---

## Audit baseline (findings from Phase 4 code review)

| Area | Current state |
|---|---|
| Error toasts | `app_root` handles 4 of 8 codes; `game_table` shows raw text; `lobby_screen` handles none |
| Double-send guard | Tile play protected by `_ui` state machine; Start/Leave/Play-Again buttons unguarded |
| Empty-name guard | Silently ignores empty input — no user feedback |
| Animations | Only hand hover-lift exists (`hand.gd:44`); no SFX infrastructure anywhere |
| Touch targets | End zones 20×31 px and End-Game button 110×32 px are below the 44 px minimum |
| Audio | Zero: no `AudioBusLayout`, no assets, no code |

---

## Task 1 — Quality pass (no new UI, fix existing gaps)

These are pure correctness fixes; do them first so later tasks build on solid ground.

### 1.1 Complete error toast coverage

**Files:** `client/scenes/app_root.gd`, `client/scenes/game_table.gd`,
`client/scenes/lobby_screen.gd`

Full error code set (`core/protocol.gd` lines 42–49):

| Code | Where it can arrive | Correct toast |
|---|---|---|
| `E_BAD_INTENT` | anywhere | "Internal error — please refresh" |
| `E_NOT_YOUR_TURN` | game_table | "Not your turn" |
| `E_ILLEGAL_MOVE` | game_table | "Illegal move" |
| `E_NOT_HOST` | game_table | "Only the host can do that" |
| `E_ROOM_NOT_FOUND` | app_root ✓ | already handled |
| `E_ROOM_FULL` | app_root ✓ | already handled |
| `E_ROOM_IN_PROGRESS` | app_root ✓ | already handled |
| `E_UPDATE_REQUIRED` | app_root ✓ | already handled |

Steps:
1. Add `S_ERROR` handler to `lobby_screen.gd` — forward the error code to
   `app_root` via a new `error_received(code)` signal, or just call `_toast()`
   directly (lobby already has `_net` injected).
2. In `game_table.gd`, replace the generic `_flash_status("Error: …")` on
   `S_ERROR` (line 173–174) with a `match` over the code field, using the
   table above. Game-table errors should show as the red-label toast (same
   helper style as `app_root._toast()`).

### 1.2 Empty-name guard with feedback

**File:** `client/scenes/app_root.gd`

In `_on_create_room()` and `_on_join_room()`, before calling `_save_name()` +
connecting, check `name_field.text.strip_edges().length() == 0` and call
`_toast("Please enter your name")` then `return`. No network call should be
made with an empty name.

### 1.3 Button double-send prevention

**Files:** `client/scenes/lobby_screen.gd`, `client/scenes/game_table.gd`

Pattern: disable the button immediately in its `.pressed` handler, before
sending the network message. Re-enable only if the server returns an error (so
the user can retry), or not at all if the action is one-way (leave, end game).

Buttons to guard:

| Button | File | Action |
|---|---|---|
| Start game | `lobby_screen.gd` | disable on click; re-enable on `S_ERROR` |
| Leave room | `lobby_screen.gd` | disable on click (one-way) |
| Play again | `game_table.gd` round-over overlay | disable on click (one-way) |
| End game | `game_table.gd` | disable on click; re-enable on `S_ERROR` |

Acceptance:
- ✅ All 8 error codes produce a visible toast in the correct screen.
- ✅ Creating/joining a room with an empty name shows "Please enter your name"
  toast and makes no network call.
- ✅ Rapid double-click on Start/Leave/Play-Again sends the server message
  exactly once (verify by adding a print in `NetworkConnection.send()` and
  clicking quickly).

---

## Task 2 — Animations

Attach to existing event hooks. All tweens use `create_tween()` (same pattern
as `hand.gd:44`). No new Node types needed.

### 2.1 Tile-play slide-in

**File:** `client/scenes/board_line.gd` → `set_line()`

After rebuilding the row, animate the **last tile** (the newly played one)
sliding in from outside the board edge rather than appearing instantly:
- Save the new tile's final `position.x` after layout.
- Set its initial `position.x` to `size.x + tile_w` (off right) or `-tile_w`
  (off left) depending on the `end` side ("R" or "L").
- Tween to final position over 0.18 s, `TRANS_QUAD / EASE_OUT`.
- `board_line` needs to know which end was played: add optional param
  `played_end: String = ""` to `set_line()`.
- `game_table._on_tile_played()` passes `msg["end"]` through.

### 2.2 Deal-in stagger

**File:** `client/scenes/hand.gd` → `set_hand()`

When tiles first appear (game start or reconnect resync), stagger each tile's
appearance instead of all appearing at once:
- In `set_hand()`, after creating all TileFace nodes, set each to
  `modulate.a = 0` and `position.y += 30` (below final position).
- Tween each tile to `modulate.a = 1` and final y over 0.15 s, staggered by
  `i * 0.06 s` (so a 5-tile hand staggers over 0.24 s total).

### 2.3 Opponent tile-count decrement

**File:** `client/scenes/opponent_seat.gd` → `set_count()`

When an opponent plays a tile, one back disappears. Make it feel intentional:
- Before clearing and rebuilding, if the new count is `old - 1`, tween the
  **last back** to `modulate.a = 0` over 0.1 s, then queue_free, then rebuild.
- Store `_count` as a field so you can detect increment vs decrement.
- If count increases or jumps (reconnect), rebuild instantly (no animation).

### 2.4 Active-seat glow fade

**File:** `client/scenes/opponent_seat.gd` → `set_active()`

Replace the instant `_glow.visible = true/false` toggle with a short fade:
- On activate: `_glow.modulate.a = 0`, make visible, tween `modulate.a` to
  `1.0` over 0.2 s.
- On deactivate: tween `modulate.a` to `0.0` over 0.15 s, then hide.

### 2.5 Round-over overlay

**File:** `client/scenes/game_table.gd` → `_show_round_over()`

The overlay currently appears instantly. Add:
- Start the overlay at `modulate.a = 0`, tween to `1.0` over 0.3 s,
  `TRANS_SINE / EASE_OUT`.
- For a DOMINO win: after the fade, add a simple `CPUParticles2D` burst
  (one-shot, `amount=40`, `spread=180`, velocity `randf * 200`, gravity `50`,
  lifetime `1.0 s`) centered on the overlay.
- For a BLOCKED end: instead of confetti, add a `Label` with text "BLOCKED"
  in large red type, starting at `scale = Vector2(2, 2)` and tweening to
  `Vector2(1, 1)` over 0.25 s (stamp effect).

### 2.6 Pass banner

**File:** `client/scenes/game_table.gd` → `_on_event()` `S_PLAYER_PASSED` branch (line 159–164)

Currently sets `_banner` text immediately. Change to:
- Show banner with `modulate.a = 1`, hold 1.2 s, tween `modulate.a` to `0`
  over 0.4 s (fade out), then call `_hide_banner()`.
- Use a single `create_tween()` with two steps (`tween_interval` then
  `tween_property`).

Acceptance:
- ✅ Playing a tile shows it slide into the board from the correct side.
- ✅ Hand tiles deal in with a stagger on game start.
- ✅ Opponent tile count drops with a brief fade before rebuild.
- ✅ Active-seat glow fades in/out rather than snapping.
- ✅ Round-over overlay fades in; DOMINO shows particle burst, BLOCKED shows stamp.
- ✅ Pass banner fades out on its own after 1.2 s.

---

## Task 3 — SFX

Build the audio system from scratch; CC0 sources only (Kenney.nl audio packs
are the recommended source).

### 3.1 Audio infrastructure

1. Create `res://assets/audio/` directory.
2. Add an `AudioBusLayout` resource (`audio_bus_layout.tres`) with two buses:
   Master and SFX. Wire in `project.godot`:
   `audio/buses/default_bus_layout = "res://assets/audio/audio_bus_layout.tres"`.
3. Add `res://client/sfx.gd` — a singleton autoload (`Sfx`) that owns five
   `AudioStreamPlayer` nodes (one per sound) and a `muted: bool` property
   backed by `ConfigFile` at `user://gaple.cfg` (same file as player name).

```gdscript
class_name Sfx
extends Node

const _KEYS := ["deal", "place", "pass", "win", "lose"]
var _players: Dictionary = {}   # key -> AudioStreamPlayer
var muted := false :
    set(v):
        muted = v
        _save()

func play(key: String) -> void:
    if muted or not _players.has(key): return
    _players[key].play()

func _ready() -> void:
    _load_config()
    for k in _KEYS:
        var p := AudioStreamPlayer.new()
        p.bus = "SFX"
        add_child(p)
        _players[k] = p
        var path := "res://assets/audio/%s.ogg" % k
        if ResourceLoader.exists(path):
            p.stream = load(path)
```

4. Add `Sfx="*res://client/sfx.gd"` to `[autoload]` in `project.godot`.

### 3.2 Asset sourcing

Download five CC0 `.ogg` files from Kenney's *UI Audio* or *Casino* pack and
save as:

| File | Event |
|---|---|
| `assets/audio/deal.ogg` | Game start / hand dealt |
| `assets/audio/place.ogg` | Tile placed on board |
| `assets/audio/pass.ogg` | Any seat passes |
| `assets/audio/win.ogg` | Local player wins |
| `assets/audio/lose.ogg` | Local player loses (someone else wins) |

### 3.3 Playback wiring

Call `Sfx.play(key)` from the existing event handlers:

| Event | Key | Location |
|---|---|---|
| `S_GAME_STARTED` | `"deal"` | `game_table._on_game_started()` |
| `S_TILE_PLAYED` | `"place"` | `game_table._on_tile_played()` |
| `S_PLAYER_PASSED` | `"pass"` | `game_table._on_event()` S_PLAYER_PASSED branch |
| `S_ROUND_OVER` winner == my seat | `"win"` | `game_table._on_round_over()` |
| `S_ROUND_OVER` winner != my seat | `"lose"` | `game_table._on_round_over()` |

### 3.4 Mute toggle

Add a mute button (🔊 / 🔇) to `game_table`'s top-right corner (next to the
countdown label). On press, toggle `Sfx.muted` (which persists to
`user://gaple.cfg`). Also add it to `app_root`'s menu screen.

Acceptance:
- ✅ Each of the five events produces a distinct sound.
- ✅ Mute toggle silences all SFX and persists across page refreshes.
- ✅ GUT suite still green (Sfx autoload absent in headless tests; guard with
  `if has_node("/root/Sfx")`).

---

## Task 4 — Mobile browser pass

### 4.1 Touch target sizing

Minimum: 44 px in every interactive dimension. Changes needed:

| Element | Current | Fix |
|---|---|---|
| End-game button | 110 × 32 | raise height to 44 |
| Join-room button | 120 × 36 | raise height to 44 |
| Room-code LineEdit | 120 × 36 | raise height to 44 |
| Name LineEdit | 200 × 36 | raise height to 44 |
| End drop zones | 20 × 31 | raise width to 44 (`board_line.gd`) |

In `board_line.gd` the left/right zone width is `20` (line 73). Change to `44`
and re-centre accordingly.

### 4.2 Portrait layout

The game is currently fixed 1280 × 720. In `project.godot`:

```ini
[display]
window/size/viewport_width=720
window/size/viewport_height=1280
window/size/initial_position_type=0
window/stretch/mode="canvas_items"
window/stretch/aspect="expand"
```

This makes the base canvas portrait. Adjust the layout constants in
`game_table.gd` so at 720 × 1280 the board sits in the middle third and the
hand stays at the bottom:
- `_board` rect: `Rect2(60, 360, 600, 200)`
- `_hand` rect: `Rect2(60, 580, 600, 240)`
- Top opponent: `Rect2(220, 40, 280, 280)`
- Left opponent: `Rect2(10, 360, 80, 500)`
- Right opponent: `Rect2(630, 360, 80, 500)`

Verify the existing `stretch/aspect=expand` already handles the 1280 × 720
landscape browser window (the canvas simply letterboxes or expands).

### 4.3 Loading screen

Godot's Web export supports a custom HTML shell and a progress bar. In
`export_presets.cfg`, set `html/custom_html_shell` to a minimal shell that
shows a spinner and the Gaple title while the wasm loads. A ready-made shell
from the Godot docs works; customise colours to match the dark theme
(`0x111921` background, `#FFD744` accent).

Acceptance:
- ✅ All interactive elements have at least 44 px in every tap dimension.
- ✅ Game is playable on a mid-range Android Chrome and iOS Safari (portrait).
- ✅ Landscape on desktop still works (canvas scales correctly).
- ✅ Web export shows a loading screen while wasm downloads.

---

## Task 5 — Test coverage for new code

The GUT suite must stay green throughout. New code that needs tests:

| Test | Location |
|---|---|
| All 8 error codes produce a toast in the correct screen | `test_ui_smoke.gd` — drive `AppRoot` / `GameTable` with fake net events |
| Empty name blocks create/join and shows toast | `test_ui_smoke.gd` |
| Sfx.play() no-ops when muted and when asset missing | new `test_sfx.gd` |
| `set_line()` with played_end slides last tile (check final position) | `test_game_table.gd` |

Headless GUT: `Sfx` autoload will not be present — guard every `Sfx.play()` call:
```gdscript
if has_node("/root/Sfx"):
    Sfx.play("place")
```

---

## Task 6 — README screenshots

Once the mobile layout is working, add two PNG screenshots to `docs/screenshots/`:
- `docs/screenshots/game_table_desktop.png` — in-progress 4-player game, desktop
- `docs/screenshots/game_table_mobile.png` — in-progress 2-player game, portrait mobile

Reference them in `README.md` under a new **Screenshots** section.

---

## Acceptance criteria (Phase 6 complete when all pass)

- ✅ All 8 error codes produce a visible, human-readable toast in the correct screen.
- ✅ Double-clicking Start/Leave/Play-Again sends the intent to the server exactly once.
- ✅ Empty name shows feedback toast; no network call is made.
- ✅ All 6 animation events (slide-in, deal stagger, opponent decrement, glow fade,
  round-over, pass banner) are visible and do not block input.
- ✅ All 5 SFX play on the correct events; mute persists across refreshes.
- ✅ Game is comfortably playable on a mid-range phone in portrait (all tap targets ≥ 44 px).
- ✅ Desktop landscape still works; no regressions in the GUT suite.
- ✅ Loading screen shown during wasm download.
