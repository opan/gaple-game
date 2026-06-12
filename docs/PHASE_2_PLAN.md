# Phase 2 — Detailed Implementation Plan: Local Single-Player

This is the executable, deep-dive plan for Phase 2 of `PLAN.md` §5. It refines
the master plan against what Phase 1 actually produced. Read `PLAN.md` §5/§7.1,
`docs/GAME_RULES.md` §8, and `docs/adr/ADR-004-bot-ai.md` first.

**Goal:** the user plays a full offline Gaple round against 1–3 bots with the
whiteboard table UI, before any networking exists. The client renders only from
"wire-shaped" events emitted by a `LocalGameDriver`, so Phase 4 swaps the driver
for a real network connection without touching the UI.

**Phase 2 is done when** all acceptance criteria in §11 pass.

---

## 1. What Phase 1 gives us (the contract Phase 2 builds on)

The pure engine (`core/`) is complete and tested. Phase 2 consumes exactly:

- `GapleGame.new_round(num_players, seed, opener_override := -1) -> GapleGame`
- `game.state` (a `GameState`): `current_seat`, `forced_opening_tile`,
  `phase` (`DEALT`/`PLAYING`/`ROUND_OVER`), `winner_seat`, `end_reason`,
  `num_players`, `left_end`, `right_end`, `line`, `hands`.
- `game.legal_moves(seat) -> Array` of `{ "tile_id": int, "end": "L"|"R" }`
  (already de-duped: a tile that matches both equal ends is listed once).
- `game.apply(intent) -> { ok, error, events }`.
- `game.pip_count(seat)`, `GapleGame.round_scores(state)`,
  `game.state.public_dict()`, `game.state.hand_dict(seat)`.

**Engine events** (`apply().events`, each has a `"type"` key):
`tile_played`, `player_passed`, `turn_started`, `round_over`. See §3 for how
these map onto wire messages — they are NOT identical to the §6 wire shapes.

---

## 2. Refinements to the master plan (the re-review result)

These deviations from `PLAN.md` §5/§7.1 are intentional and explained here so the
implementer doesn't "correct" them back:

| # | Master plan said | Phase 2 does instead | Why |
|---|---|---|---|
| R1 | (protocol table lives in Phase 3 §6) | **Build `core/protocol.gd` first**, as Phase 2 Step 0 | The UI renders from wire messages; the contract must exist and be stable before the UI or the Phase 3 server. Both share this one file. |
| R2 | `LocalGameDriver` is a `RefCounted` | `LocalGameDriver` **extends `Node`** | It needs `get_tree().create_timer()` for humanized bot delays (§5). A `RefCounted` has no tree access. |
| R3 | Tile art = atlas generated at build time (§7.1) | Tiles **drawn at runtime** via a `TileFace` control's `_draw()` | Zero image assets → smaller web bundle, trivially themeable, no build step. A domino face is just a rounded rect + divider + pip dots. |
| R4 | `turn_started`/`round_over` are events | The driver **enriches** them (deadline, pip_counts, scores, scoreboard) | The pure engine has no clock or cumulative scoreboard; that data is added by the driver (Phase 2) and identically by the server (Phase 3). |

None of these change the game design or the ADRs; they make the seams explicit.

---

## 3. Step 0 — `core/protocol.gd` (the wire contract)

A pure `RefCounted` owning message-type constants, the version stamp, builder
functions, and the engine-event → wire-message translation. Both the Phase 2
driver and the Phase 3 server use it verbatim.

```gdscript
class_name Protocol
extends RefCounted

const VERSION := 1

# Server -> client types
const S_GAME_STARTED := "game_started"
const S_HAND := "hand"
const S_PUBLIC_STATE := "public_state"
const S_TILE_PLAYED := "tile_played"
const S_PLAYER_PASSED := "player_passed"
const S_TURN_STARTED := "turn_started"
const S_ROUND_OVER := "round_over"
const S_ERROR := "error"
# (Phase 3 adds: welcome, room_state, player_replaced_by_bot, player_reclaimed)

# Client -> server types (defined now, used by Phase 3/4)
const C_HELLO := "hello"
const C_PLAY_TILE := "play_tile"
const C_PASS := "pass"
const C_START_GAME := "start_game"
# (… create_room, join_room, add_bot, remove_bot, end_game, play_again, leave_room)

# Error codes (Phase 3 emits these; defined here as the single source)
const E_BAD_INTENT := "BAD_INTENT"
const E_NOT_YOUR_TURN := "NOT_YOUR_TURN"
const E_ILLEGAL_MOVE := "ILLEGAL_MOVE"
# (… NOT_HOST, ROOM_NOT_FOUND, ROOM_FULL, ROOM_IN_PROGRESS, UPDATE_REQUIRED)

## Stamp any payload with its type + protocol version.
static func msg(t: String, payload: Dictionary = {}) -> Dictionary

## Convenience builders (return fully-stamped messages):
static func game_started(num_players: int, opener_seat: int, opening_tile_id: int) -> Dictionary
static func hand(tile_ids: Array) -> Dictionary
static func public_state(public_dict: Dictionary) -> Dictionary
static func turn_started(seat: int, deadline_unix_ms: int = -1) -> Dictionary
static func round_over(reason: String, winner_seat: int, pip_counts: Array, scores: Array, scoreboard: Array) -> Dictionary
static func error(code: String, message: String) -> Dictionary

## Translate a raw engine event into a wire message. Renames "type"->"t",
## stamps "v", and merges `enrich` (e.g. deadline for turn_started, or
## pip_counts/scores/scoreboard for round_over).
static func from_engine_event(ev: Dictionary, enrich: Dictionary = {}) -> Dictionary
```

**Mapping table (engine event → wire message):**

| Engine event (`type`) | Wire message (`t`) | Enrichment the driver/server adds |
|---|---|---|
| `tile_played` | `tile_played` | none (engine event already has all fields) |
| `player_passed` | `player_passed` | none |
| `turn_started` | `turn_started` | `deadline_unix_ms` (Phase 2: `-1`/omitted; no timer) |
| `round_over` | `round_over` | `pip_counts[]`, `scores[]`, `scoreboard[]` |

**Synthesized at round start (not engine events):** `game_started`
(`num_players`, `opener_seat = state.current_seat`, `opening_tile_id =
state.forced_opening_tile`), `hand` (the human's `hand_dict`), `public_state`,
and the first `turn_started`.

**Tests — `tests/unit/test_protocol.gd`:** every builder stamps `t` and
`v=VERSION`; `from_engine_event` renames `type`→`t` and merges enrichment;
`round_over` carries the score arrays.

---

## 4. Step 1 — `core/bot_policy.gd` (ADR-004 Greedy+)

Pure `RefCounted`. Sees only what a human in that seat sees (own hand + public
state) — no hidden info.

```gdscript
class_name BotPolicy
extends RefCounted

enum Difficulty { EASY, NORMAL, HARD }   # v1 ships NORMAL; EASY used for fuzz variety
var difficulty: int

func _init(diff: int = Difficulty.NORMAL) -> void

## legal: Array of {tile_id, end}. hand_ids: the bot's own tiles. Returns one
## chosen move dict, or {} if legal is empty (caller then passes).
func choose_move(public_state: Dictionary, hand_ids: Array, legal: Array, rng: RandomNumberGenerator) -> Dictionary
```

**NORMAL priority (ADR-004), applied to the tile:**
1. **Win:** if the bot's hand has 1 tile, play it (empties the hand → wins).
2. **Dump doubles:** prefer a move whose tile is a double (riskiest to be stuck with).
3. **Highest pips:** otherwise the tile with the largest pip sum (minimizes
   blocked-game penalty, GAME_RULES §7).
4. **Tie-break:** keep the most distinct pip values in hand; then `rng` pick.

After choosing a tile, pick an end: if the tile has two legal ends, either is
fine — choose `"L"` deterministically (end choice is strategically neutral for
Greedy+). **EASY** = uniform random legal move. **HARD** = reserved (not v1).

**Tests — `tests/unit/test_bot.gd`:** winning move taken at hand-size 1; double
preferred over non-double; highest-pip preferred with no doubles; over 1000
seeded random games the returned move is always a member of `legal` (never
illegal).

---

## 5. Step 2 — `client/local_game_driver.gd` (`extends Node`)

Owns one `GapleGame`, the bots for non-human seats, and the cumulative
scoreboard. Emits wire messages so the UI is transport-agnostic.

```gdscript
class_name LocalGameDriver
extends Node

signal event_received(msg: Dictionary)   # identical shape to the network path

var bot_delay := Vector2(0.8, 2.0)        # seconds; tests set Vector2.ZERO

func start(num_players: int, human_seat: int = 0, game_seed: int = -1) -> void
func submit_play(tile_id: int, end: String) -> void   # UI calls on human turn
func submit_pass() -> void                            # UI calls for a forced human pass
func legal_moves_for_human() -> Array                 # UI asks for highlight info
func human_seat() -> int
func play_again() -> void                             # winner opens next round (free)
```

**Event flow:**

1. `start()`:
   - `_game = GapleGame.new_round(N, seed)`; create a `BotPolicy` for every
     non-human seat (all of 1..N-1 in Phase 2).
   - Emit `game_started`, `hand` (human's tiles), `public_state`,
     `turn_started(opener)`.
   - Call `_drive()`.
2. `_drive()` loop, while `_game.state.is_active()`:
   - `seat = current_seat`, `moves = legal_moves(seat)`.
   - **Human seat:** `return` (hand control to UI) — whether or not `moves` is
     empty. The UI decides: if empty it shows the "No playable tile — passing…"
     banner for 1.5 s then calls `submit_pass()`; otherwise it waits for a tap.
   - **Bot seat:** `await get_tree().create_timer(randf bot_delay).timeout`;
     then `apply` a pass (if `moves` empty) or `bot.choose_move(...)`.
3. `submit_play` / `submit_pass` → `_apply(intent)` → `_drive()`.
4. `_apply(intent)`: `res = _game.apply(intent)`; for each engine event, build
   the enriched wire message via `Protocol.from_engine_event` and emit it. On a
   `round_over` event, compute `pip_counts` (per seat), `scores`
   (`round_scores`), update `_scoreboard`, and include all three.

**Why the UI handles the human forced-pass (not the driver):** keeps all human
turn timing in the UI and the driver purely reactive to human turns — mirrors
the Phase 4 network path where the server sends `turn_started` and the client
reacts. The driver only owns *bot* pacing.

**Tests — `tests/unit/test_local_driver.gd`** (set `bot_delay = Vector2.ZERO`,
`await` each step): a 2-player human+bot game emits a well-formed event sequence
starting with `game_started`/`hand`/`public_state` and ending in exactly one
`round_over`; the human is never auto-played; emitted `tile_played` counts match
tiles leaving hands.

---

## 6. Rendering primitives

### 6.1 `client/scenes/tile_face.gd` (`extends Control`, custom `_draw()`)
- Exports `low: int`, `high: int`, `face_up: bool`, `orientation` (vertical /
  horizontal), `state` (normal / selected / disabled).
- `_draw()`: rounded rect body; centre divider line; pip dots per end using the
  standard dice layout below. Face-down draws a patterned back instead.
- Pip positions (per half, a 3×3 grid; • = lit for that value):
  ```
  0:           1:           2:  •         3:  •        4: • •       5: • •      6: • •
                   •            •              •          •   •       •   •      • • •  (mid row for 6)
               •            •            •                •   •      •   •      • • •
  ```
  Implement as a fixed map `value -> Array[Vector2]` of normalized dot centres.
- Disabled = desaturated/dimmed; selected = raised + outline glow.

### 6.2 `client/scenes/tile_node.tscn` + `.gd`
Wraps a `TileFace`; adds input (clicked signal), hover lift tween, and the
selected/disabled visual states driven by the parent scene.

---

## 7. Step 3 — Table scenes

Node trees (Control-based, anchored; the 1280×720 `canvas_items` stretch handles
scaling):

- **`game_table.tscn`** (root `Control`):
  - `LocalGameDriver` (Node child) — added at runtime by the menu.
  - `BoardLine` (centre) — the played-tile chain with two highlightable ends.
  - `Hand` (bottom) — the local player's fanned tiles.
  - `OpponentSeat` ×(N−1) placed at TOP/LEFT/RIGHT per §9 mapping.
  - `TurnIndicator` overlay (highlights the active seat).
  - `Banner` (forced-pass / "you must open with X" hints).
  - Connects to `driver.event_received` and dispatches per message `t`.
- **`board_line.tscn`**: lays out `TileNode`s in a horizontal chain inside a
  `CenterContainer`; auto-scales down (min 0.5) when wider than 70 % of the
  viewport (≤20 tiles always fit). Exposes `highlight_end("L"/"R"/both/none)`.
- **`hand.tscn`**: arranges 1–5 `TileNode`s on an arc (rotation
  `lerp(-18°, +18°)` across the hand); hover raises a tile 16 px; emits
  `tile_clicked(tile_id)`.
- **`opponent_seat.tscn`**: name label + face-down tile count; renders a small
  fanned/stacked set of card-backs (TOP vertical; LEFT/RIGHT rotated 90°). The
  count animates down when that seat plays.
- **`round_over.tscn`**: winner + reason (Domino / Blocked / Aborted), a pip
  table per seat, cumulative scoreboard, and **Play again** + **Back to menu**.

---

## 8. Step 4 — Interaction state machine (`game_table.gd`)

Local UI states: `WAITING` (not human's turn) → `IDLE` (human turn, no tile
picked) → `TILE_PICKED` (a tile selected, ends may be highlighted) → back to
`WAITING` after a play/pass.

On `turn_started(seat == human)`:
- `moves = driver.legal_moves_for_human()`.
- If empty → show "No playable tile — passing…" banner, `await` 1.5 s,
  `driver.submit_pass()`.
- Else → enter `IDLE`. For each hand tile, enable it iff it appears in `moves`;
  disable (desaturate, non-interactive) the rest. If the board is empty and a
  forced opener applies, only the forced tile is enabled — also show "You must
  open with [X|Y]".

On hand `tile_clicked(tile_id)` in `IDLE`:
- Gather that tile's legal ends from `moves`.
- **One end** → `driver.submit_play(tile_id, end)` immediately.
- **Two ends** → enter `TILE_PICKED`: glow both board ends; the next click on a
  board end (or on an end-affordance) calls `submit_play(tile_id, chosen_end)`.
  Clicking the tile again or another tile cancels/reselects.

The UI **never** sends an illegal intent because it only offers moves from
`legal_moves_for_human()`. (The driver/engine still rejects illegal intents as a
backstop — that's what the acceptance test in §11 pokes at.)

On `tile_played` / `player_passed` for any seat: animate (see §10), update
opponent counts, re-render the board line and ends.

On `round_over`: open `round_over.tscn` with the payload.

---

## 9. Seat → screen mapping (from the whiteboard, GAME_RULES §8)

Local player is always at the **bottom**. For logical seat `s` with local seat
`L` and `N` players: `rel = (s - L + N) % N`, then:

| N | rel 1 | rel 2 | rel 3 |
|---|---|---|---|
| 2 | TOP | — | — |
| 3 | RIGHT | LEFT | — |
| 4 | RIGHT | TOP | LEFT |

`rel 0` is always the local player (bottom). Encode as a constant lookup keyed
by `N`. In Phase 2, `L = 0`.

---

## 10. Step 5 — Animations (Tweens; keep them short, ~0.2–0.3 s)

- Deal-in: tiles stagger into the hand / opponent stacks at round start.
- Play: the played tile flies from its origin to the chosen board end (~0.25 s);
  opponent plays flip a card-back to a face at the line.
- Pass: brief "PASS" tag over the passing seat.
- Win: confetti (`CPUParticles2D`); Blocked: a "LOCKED" stamp on the board.
- Turn indicator: pulse/glow on the active seat.

Animations are cosmetic; gameplay state always comes from driver events.

## 10.1 Step 6 — Menu hook
A **Practice vs bots** entry that asks for opponent count (1–3 → N = 2–4),
instantiates `game_table.tscn`, adds a `LocalGameDriver`, and calls
`start(N, 0)`. In Phase 2 this can be a minimal scene/button; Phase 4 folds it
into the full `main_menu.tscn`.

---

## 11. Acceptance criteria (Phase 2 done = all green)

- ✅ A full round vs 3 bots is playable start→finish with mouse only.
- ✅ A blocked game is reachable and `round_over.tscn` shows the correct
  pip-count winner.
- ✅ The UI never permits an illegal move; the engine rejects wrong-turn /
  wrong-tile / wrong-end intents (covered by `test_local_driver.gd` +
  Phase 1 `test_rules.gd`).
- ✅ Forced opener: when the human is the opener, only the forced tile is
  playable and the hint is shown.
- ✅ Unit tests green: `test_protocol.gd`, `test_bot.gd`, `test_local_driver.gd`
  (plus all Phase 1 tests still pass).
- ✅ Runs in a browser via a local Web export served with COOP/COEP headers
  (Godot editor "Remote Debug → Run in Browser", or `python tools/serve_web.py`
  that injects the headers).

## 12. Task order & dependencies

```
Step 0  core/protocol.gd        + test_protocol.gd      (no deps)
Step 1  core/bot_policy.gd      + test_bot.gd           (deps: core)
Step 2  client/local_game_driver.gd + test_local_driver.gd (deps: 0,1)
Step 3a tile_face.gd / tile_node.tscn                   (deps: none; visual)
Step 3b board_line, hand, opponent_seat                 (deps: 3a)
Step 4  game_table.gd interaction wiring                (deps: 2,3)
Step 5  round_over.tscn + scoreboard                    (deps: 2)
Step 6  Practice-vs-bots menu hook                      (deps: 4,5)
Step 7  animations polish                               (deps: 4)
Step 8  browser export + COOP/COEP serve script + verify (deps: all)
```

Steps 0–2 are headless and fully unit-testable — do and verify them before any
scene work. Steps 3–8 are visual and verified by running the app (the `verify`/
`run` skills) plus the acceptance checks in §11.

## 13. Out of scope for Phase 2 (deferred)

Networking, lobby, rooms, turn countdown timer/`deadline_unix_ms` rendering,
reconnect, host controls, SFX (Phase 6), the standalone client-side legal-move
helper (added in Phase 4 when the UI no longer has the full `GapleGame`).
