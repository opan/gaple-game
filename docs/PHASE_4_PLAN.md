# Phase 4 — Detailed Implementation Plan: Networked Client

Executable deep-dive for Phase 4 of `PLAN.md` §7, reconciled against the actual
Phase 1–3 code. Read `PLAN.md` §7, `docs/PHASE_3_PLAN.md`, `core/protocol.gd`,
`client/scenes/game_table.gd`, and `client/local_game_driver.gd` first.

**Goal:** play Gaple online against other people and bots. Create/join a room by
code, see a lobby, play through the authoritative server, and survive a
mid-round disconnect by reconnecting. The **same `game_table` UI** must drive
both online play and the existing local "Practice vs bots" — only the event
source changes.

**Phase 4 is done when** all acceptance criteria in §11 pass.

---

## 1. What Phases 1–3 give us

- **`game_table.gd` already renders from wire messages** and maintains a local
  view of the public board from events (`_line`, `_left_end`, `_right_end`,
  `_human_hand`, …). But it asks the **driver** for two things it can't get over
  a network: `legal_moves_for_human()` and `human_seat()` (lines 155/165/171,
  and `submit_pass` at 178). Removing that coupling is the heart of Phase 4.
- **`LocalGameDriver`** is the local event source/intent sink. The server `Room`
  is the networked equivalent and behaves slightly differently: it **auto-passes
  stuck seats** (R1) and **sends each client its seat** in the `hand` message
  (added Phase 3). We align the local path to match so the UI is written once.
- **`core/protocol.gd`** — the full wire contract (now with inbound parse +
  `hand.seat`). The client reuses it for sending and parsing.
- **Server transport is raw WebSockets** (`TCPServer`/`accept_stream`); the
  client uses a raw `WebSocketPeer` and the same JSON framing. JSON numbers
  arrive as floats → `int(...)`.

---

## 2. Architecture decisions (the re-review result)

| # | Issue | Decision | Why |
|---|---|---|---|
| R1 | `game_table` asks the driver for legal moves; over a network there is no client-side engine | **Client computes its own legal moves** from its local view via a new pure `core/legal.gd`; the server stays authoritative (rejects illegal) | ADR-003: the client may compute highlights from public state + own hand. This is the Phase-4 helper the earlier plans deferred. |
| R2 | Local driver waits for a stuck human + `submit_pass`; server auto-passes | **Align the local driver to auto-pass stuck seats** like the Room; the client **never sends `pass`** | One behavior, one UI path. Forced pass becomes a reactive toast on `player_passed(me)`. |
| R3 | `game_table` calls `driver.human_seat()` | **Track my seat from the `hand` message's `seat` field** | Works identically local and online; no engine needed. |
| R4 | `game_table` creates its own `LocalGameDriver` | **Inject a `GameClient`** (the driver *or* the network connection) | Same table, two sources. The menu wires which one. |
| R5 | (no client transport) | **`NetworkConnection` autoload**: raw `WebSocketPeer`, JSON, reconnect-with-token, polled in `_process` | Mirrors the server's framing; one global connection for the session. |
| R6 | (reconnect) | **Reuse the server's resync** (`game_started`/`public_state`/`hand`/`turn_started`); `game_table` already rebuilds its model from those | Reconnect is mostly free once R1–R4 land. |

R1, R2, and R4 touch working Phase 2/3 code (driver + game_table), guarded by the
existing suite — update those tests alongside.

---

## 3. The `GameClient` abstraction (Step 1)

Define the minimal surface `game_table` needs, implemented by both sources:

```gdscript
# An interface (duck-typed; both extend Node and provide these):
signal event_received(msg: Dictionary)   # wire messages, identical shape both ways
func submit_play(tile_id: int, end_side: String) -> void
func play_again() -> void                 # host action (no-op/ignored if not host)
func leave() -> void
```

Note what is **gone**: `submit_pass` (R2 — nobody sends pass) and
`legal_moves_for_human`/`human_seat` (R1/R3 — the table derives these itself).

- **`LocalGameDriver`** already has `submit_play`/`play_again`; add `leave()`,
  delete `submit_pass`/`legal_moves_for_human`/`human_seat`, and change `_drive`
  to break only when the human has a legal move (auto-pass otherwise), matching
  `Room._drive`.
- **`NetworkConnection`** maps `submit_play` → send `play_tile`, `play_again` →
  send `play_again`, `leave` → send `leave_room`; emits `event_received` for each
  inbound server message.

---

## 4. Client-side legal moves (`core/legal.gd`, Step 0)

Extract the pure matching logic so both the engine and the client use one copy:

```gdscript
class_name Legal
extends RefCounted

## Legal moves for a hand given the open board, with no full GameState. Mirrors
## GapleGame.legal_moves exactly. is_opening = board empty; forced_tile_id = the
## round-1 forced opener (or -1). Returns Array of {tile_id, end}.
static func moves_for(left_end: int, right_end: int, is_opening: bool, forced_tile_id: int, hand_ids: Array) -> Array
```

`GapleGame.legal_moves` is refactored to delegate to `Legal.moves_for(...)` (so
the server and client provably agree). `test_legal.gd` checks it against the
engine over many random states.

---

## 5. `game_table` refactor (Step 1)

- Constructor/usage: `start_with(client: Node)` instead of creating a driver.
  (`Practice` passes a `LocalGameDriver`; online passes the `NetworkConnection`.)
- Track `_my_seat` from the `hand` message (`m["seat"]`); drop
  `_driver.human_seat()`.
- `_legal_moves_for_me()` = `Legal.moves_for(_left_end, _right_end,
  _line.is_empty(), _opening_tile_id, _human_hand)`; drop
  `_driver.legal_moves_for_human()`.
- Forced pass (R2): delete the banner-then-`submit_pass` path. Instead, on
  `player_passed` where `seat == _my_seat`, flash "No playable tile — passed."
- `_submit` → `_client.submit_play`; `_on_play_again` → `_client.play_again`.
- Turn timer (§8): on `turn_started`, if `deadline_unix_ms > 0`, show a countdown
  ring on the active seat; `-1` (local) shows none.

Update `test_game_table*.gd` to the new entry point and the reactive pass.

---

## 6. `NetworkConnection` autoload (Step 2)

```gdscript
# client/net/connection.gd  (autoload "Net")
extends Node
signal event_received(msg: Dictionary)
signal connection_changed(state: String)   # connecting/open/reconnecting/closed

var server_url: String                      # from client/net/config.gd (ADR-005)
func connect_to_server() -> void
func hello(player_name: String) -> void
func create_room() -> void
func join_room(code: String) -> void
func add_bot() -> void
func remove_bot(seat: int) -> void
func start_game() -> void
func submit_play(tile_id: int, end_side: String) -> void
func end_game() -> void
func play_again() -> void
func leave() -> void
```

- Raw `WebSocketPeer`; `_process` polls, drains packets → `JSON.parse_string`
  → `event_received.emit`. Send = `ws.send_text(JSON.stringify(msg))`.
- Handshake: on open, send `hello{name, session_token?}`; store `session_token`
  from `welcome` in a `ConfigFile` under `user://` (also used for reconnect).
- **Auto-reconnect:** on unexpected close while in a room, retry up to 3× with
  exponential backoff, re-`hello` with the stored token; emit
  `connection_changed`. The server reclaims the seat and resyncs (§9).
- `config.gd`: `wss://gaple-server.fly.dev` in release, `ws://localhost:9000` in
  debug, overridable via a `?server=` URL query param (ADR-005).

---

## 7. Menu, lobby, overlays (Steps 3–4)

- **`main_menu.tscn`**: name field (persisted via `ConfigFile`), buttons —
  **Practice vs bots** (local driver, existing Phase 2 path), **Create room**,
  **Join room** (code entry). Create/Join connect via `Net` then show the lobby.
- **`lobby.tscn`**: renders `room_state` — 4 seat slots (name / kind / connected),
  big shareable room code. Host controls: add/remove bot, **Start** (enabled only
  at ≥2 occupied seats); non-host shows "waiting for host". `game_started` →
  swap to `game_table` fed by `Net`.
- **Connection overlay**: a non-blocking banner driven by `connection_changed`
  ("Reconnecting…", "Connection lost"). Late join → `ROOM_IN_PROGRESS` error
  toast, stay on the menu (R3).

`app_root.gd` becomes the screen manager: menu ↔ lobby ↔ table, plus the local
practice path (unchanged).

---

## 8. In-game additions (Step 5)

- **Turn countdown ring** on the active seat from `deadline_unix_ms`
  (`Time.get_unix_time_from_system()`); hide when `-1`.
- **"Bot took over seat N" toast** on `player_replaced_by_bot`; **"Player
  reconnected"** on `player_reclaimed`.
- **Host-only End game** button → confirm dialog → `Net.end_game()`. Visible only
  when `_my_seat == host_seat` (from `room_state`).
- `round_over` overlay: cumulative scoreboard from the message; host sees **Play
  again**, others "waiting for host".

---

## 9. Reconnect flow (Step 7)

Mostly emergent from R1–R6:
1. `NetworkConnection` detects the drop, reconnects, re-`hello`s with the token.
2. Server matches the token to the disconnected seat, broadcasts
   `player_reclaimed`, and **resyncs** that peer (`game_started`,
   `public_state`, `hand`, `turn_started`).
3. `game_table._on_game_started` already resets the model; the resync rebuilds
   hand + board and play continues. Verify a browser-tab refresh mid-round
   restores and continues.

---

## 10. Testability

- **Headless, deterministic:** `test_legal.gd` (Step 0) checks `Legal.moves_for`
  equals `GapleGame.legal_moves` over random states. The driver/table refactors
  keep `test_local_driver.gd` / `test_game_table*.gd` green (updated for the new
  entry point and reactive pass).
- **`NetworkConnection` against the real server:** extend the Phase 3
  `test_ws_integration` pattern — boot `ServerMain`, drive a round through two
  `NetworkConnection`s (not raw sockets), asserting the same wire flow and that
  reconnect-with-token resyncs.
- **UI:** verified by running the app + screenshots (the `run`/`verify` skills):
  two browsers play a round on localhost; mid-game tab refresh reclaims the seat.

---

## 11. Acceptance criteria (Phase 4 done = all green)

- ✅ Two browsers (normal + incognito) play a full game on localhost.
- ✅ Host adds a bot; 2 humans + 1 bot finish a round with correct scores.
- ✅ Mid-game browser-tab refresh reclaims the seat and play continues.
- ✅ Host **End game** returns everyone to the lobby; no scores recorded.
- ✅ A late joiner gets a `ROOM_IN_PROGRESS` toast and stays on the menu.
- ✅ **Practice vs bots still works** through the same `game_table` (no regression).
- ✅ Headless suite green, incl. `test_legal.gd` and the `NetworkConnection`
  integration test.

## 12. Task order & DAG

```
Step 0  core/legal.gd (+test); GapleGame.legal_moves delegates to it
Step 1  GameClient surface; align LocalGameDriver (auto-pass, drop pass/seat/legal);
        refactor game_table (client-side legal, my_seat from hand, reactive pass);
        update Phase 2 tests                                   (deps: 0)
Step 2  client/net/connection.gd autoload + config.gd; integration test (deps: 1)
Step 3  main_menu.tscn (name persist, practice/create/join) + connection overlay (deps: 2)
Step 4  lobby.tscn (room_state, host controls, code)          (deps: 2,3)
Step 5  game_table online extras (countdown ring, toasts, host End game) (deps: 1,2)
Step 6  round_over networked (scoreboard, host play again)    (deps: 4,5)
Step 7  reconnect flow + verify                               (deps: 2,6)
Step 8  two-browser verification + web export refresh         (deps: all)
```

Steps 0–2 are headless/unit-testable; do and verify them before the scene work
(Steps 3–8), which is verified by running the app.

## 13. Out of scope for Phase 4 (deferred)

Spectators, chat, public room list / matchmaking, friend invites, the
match-target end condition, mobile-specific polish and SFX (Phase 6), and
deployment/TLS (Phase 5). This phase targets localhost + the existing web export;
production hosting is Phase 5.
