# Phase 3 — Detailed Implementation Plan: Authoritative Server

Executable deep-dive for Phase 3 of `PLAN.md` §6, reconciled against what Phases
1–2 actually built. Read `PLAN.md` §6, `docs/adr/ADR-002-multiplayer-architecture.md`,
`docs/GAME_RULES.md` §8, and `core/protocol.gd` first.

**Goal:** a headless Godot process that hosts Gaple rooms over WebSocket, is the
single source of truth for game state, mixes human and bot seats, and enforces
every rule in `GAME_RULES.md`. Clients send intents; the server validates with
`GapleGame.apply()` and broadcasts hidden-information-safe events.

**Phase 3 is done when** all acceptance criteria in §11 pass.

---

## 1. What Phases 1–2 give us

- **`core/` rules engine** (pure, tested): `GapleGame.new_round/legal_moves/
  apply`, `GameState.public_dict()/hand_dict(seat)`, `round_scores`, `pip_count`.
- **`core/protocol.gd`** — the wire contract: message-type and error-code
  constants, outbound builders, and `from_engine_event(ev, enrich)`. Phase 3
  **adds inbound parsing/validation** (§5).
- **`core/bot_policy.gd`** — `BotPolicy.choose_move(...)`, reused server-side.
- **`client/local_game_driver.gd`** — the *reference orchestrator*. The server's
  Room does the same job (deal → drive turns → run bots → enrich events →
  maintain scoreboard) but for many networked peers with per-seat redaction. The
  drift-prone part of that job — turning engine events into wire messages and
  computing scores — is small and pure; §9 extracts it into a shared `core/`
  helper that both the driver and the Room call (composition, not a base class).

Engine events (`apply().events`): `tile_played`, `player_passed`, `turn_started`,
`round_over`. The server maps these to wire messages exactly like the driver.

---

## 2. Refinements to the master plan (the re-review result)

| # | Master plan (§6) | Phase 3 does instead | Why |
|---|---|---|---|
| R1 | client sends `play_tile`; `pass` exists | **Server auto-passes** a seat with no legal move; clients never send `pass` | The server holds the hand, so it knows a pass is forced — waiting on the client just risks a stall and a wasted round-trip. The Phase 4 net client only *receives* `player_passed`. `C_PASS` stays reserved but server-driven. |
| R2 | "protocol.gd shape validation" | **Add inbound `Protocol.parse()` + per-type validation** to `core/protocol.gd` | Today protocol.gd only *builds* outbound messages. Inbound needs malformed-JSON / unknown-type / version / missing-field handling → `UPDATE_REQUIRED` / `BAD_INTENT`. |
| R3 | (server uses WebSocket directly) | **Room/RoomManager take an injected `send(peer_id, msg)` sink**, not WebSocket APIs | Lets `test_room.gd` run every scenario with a fake transport, no sockets. `server_main.gd` provides the real WS-backed sink. |
| R4 | LocalGameDriver (Phase 2) and Room are separate | **Extract the shared *pure logic* into `core/round_view.gd`** (a `RefCounted` helper) that both call — composition, not a base class (Step 0) | The drift-prone bit (engine-event → wire message + scoring) is pure and needs no Node; sharing it as a tested `core/` helper kills drift without coupling the two Nodes. Godot favors composition over deep inheritance. Each Node keeps its own thin timer/routing loop. |
| R5 | (4 physical seats, gaps) | **Contiguous logical seats 0..N−1, host = seat 0** at game start | Matches the engine (no empty seats inside `core`). The 4-seat-with-gaps lobby layout is a Phase 4 client concern; the client already maps logical→screen (GAME_RULES §8). |
| R6 | (unspecified) | **Single-threaded poll loop**; timers via deadline checks in `_process` + `SceneTreeTimer` for bot delays | No locks, no data races; simplest correct model for domino-rate traffic. |

R1 and R4 are the load-bearing decisions — confirm them before building.

---

## 3. Architecture & layers

All server code is one headless Godot tree (`godot --headless -- --server`).
`main.gd` already parses `--server`/`--port`; Phase 3 replaces its placeholder
with a real `ServerMain` boot.

```
ServerMain (Node)               server/server_main.gd
  • owns WebSocketMultiplayerPeer (create_server on --port)
  • _process: poll(); drain packets; on connect/disconnect/packet → dispatch
  • implements the real Transport sink: send(peer_id, dict) → JSON text frame
  • routes parsed client messages to SessionRegistry / RoomManager / Room
SessionRegistry                 server/session.gd
  • peer_id ↔ Session { name, session_token, room_code, seat }
  • issues session_token on hello; resolves reconnects by token
RoomManager (Node)              server/room_manager.gd
  • code (5 chars) ↔ Room; create/join/destroy; idle GC
Room (Node)                     server/room.gd
  • lobby (seat occupants, host) + the round (a GapleGame)
  • validates intents, drives turns/bots/timers, broadcasts redacted events
  • cumulative scoreboard across rounds
  • composes core/round_view.gd for event→wire + scoring (shared with the driver)
Transport (interface)           server/transport.gd
  • send(peer_id: int, msg: Dictionary); broadcast(peer_ids, msg)
  • real impl in ServerMain; fake recording impl in tests
```

---

## 4. Transport & framing

**Built with raw per-connection WebSockets, NOT `WebSocketMultiplayerPeer`.**
`WebSocketMultiplayerPeer` prepends Godot multiplayer-protocol bytes to every
packet, so a browser / wscat / any non-Godot client receives garbage instead of
clean JSON. For a browser-facing JSON protocol we accept connections manually:

- `TCPServer.listen(port)`; each frame, `take_connection()` →
  `WebSocketPeer.new()`; `ws.accept_stream(tcp)`. Assign an incrementing peer id.
- Poll every client `WebSocketPeer` each frame. On first `STATE_OPEN` →
  `server.on_connect(id)`; drain packets → `Protocol.parse(get_packet().
  get_string_from_utf8())` → `server.on_message`. On `STATE_CLOSED` →
  `server.on_disconnect(id)`.
- Send: `ws.send_text(JSON.stringify(msg))` — clean text frames every standard
  client understands.
- **JSON numbers decode as floats** (e.g. `tile_id` 11 → 11.0); the server uses
  `int(...)` everywhere it reads a numeric field. Clients should do the same.

---

## 5. Protocol additions (`core/protocol.gd`)

Add inbound handling (pure, unit-tested):

```gdscript
## Parse a raw text frame. Returns {ok:bool, msg:Dictionary, code:String}.
static func parse(text: String) -> Dictionary
    # JSON error            → {ok:false, code:E_BAD_INTENT}
    # missing/!int "v"      → {ok:false, code:E_BAD_INTENT}
    # v != VERSION          → {ok:false, code:E_UPDATE_REQUIRED}
    # missing "t"           → {ok:false, code:E_BAD_INTENT}
    # else                  → {ok:true, msg:<dict>}

## Validate a client message's required fields for its type.
static func validate_client(msg: Dictionary) -> String   # "" ok, else error code
    # play_tile needs int tile_id + end in {"L","R"}; join_room needs code; etc.
```

Server maps engine `apply()` error strings → codes:
`"not your turn"`→`NOT_YOUR_TURN`, `"illegal move"`/`"tile not in hand"`/
`"cannot pass…"`→`ILLEGAL_MOVE`, otherwise `BAD_INTENT`.

**Tests** (`test_protocol.gd` additions): bad JSON, wrong version, missing `t`,
missing required fields, and a valid `play_tile` all classify correctly.

---

## 6. Room lifecycle & message handling

State machine (GAME_RULES §8): `LOBBY → PLAYING → ROUND_OVER → (LOBBY|PLAYING)`.

**Client → server handling:**

| Message | State | Effect |
|---|---|---|
| `create_room` | — | new Room, sender = host = seat 0; reply `room_state` |
| `join_room{code}` | LOBBY | seat the joiner; broadcast `room_state`. PLAYING/ROUND_OVER → `error ROOM_IN_PROGRESS` (R3). Unknown → `ROOM_NOT_FOUND`. Full → `ROOM_FULL` |
| `add_bot`/`remove_bot` | LOBBY, host | mutate seats; broadcast `room_state`; non-host → `NOT_HOST` |
| `start_game` | LOBBY, host, ≥2 occupied | assign contiguous seats, `new_round`, go PLAYING, announce (§7) |
| `play_tile{tile_id,end}` | PLAYING, current seat | `apply`; on error → `error`; else broadcast events |
| `end_game` | PLAYING, host | `apply(abort)` → ROUND_OVER, void round (no scores) |
| `play_again` | ROUND_OVER, host | winner opens; `new_round`; PLAYING |
| `leave_room` | any | LOBBY: free seat; PLAYING: seat → bot (§8) |

Validation order (every inbound): `Protocol.parse` → `validate_client` →
room-phase/permission check → `GapleGame.apply`. Any failure → a single `error`
reply to the sender, **no** state change, **no** broadcast.

---

## 7. Round announce & hidden-information redaction

This is the core security property (ADR-002): a peer only ever receives its own
hand. On `start_game` / `play_again`:

1. Broadcast `game_started{num_players, opener_seat, opening_tile_id}` to all.
2. Broadcast `public_state{public_dict()}` to all (counts only, no hands).
3. **Send each human seat privately** `hand{hand_dict(seat)}` — never broadcast.
4. Broadcast `turn_started{seat, deadline_unix_ms = now + 30_000}`.

Per move (`apply` events → wire via `Protocol.from_engine_event`):
`tile_played`, `player_passed`, `turn_started` (with fresh deadline),
`round_over` (enriched with `pip_counts`, `scores`, `scoreboard`) — all
broadcast public. No hand contents ever ride a broadcast.

A reconnecting peer (§8) is re-sent `game_started`, `public_state`, its own
`hand`, and the current `turn_started` to resync.

---

## 8. Bots, timers, disconnect, reconnect, host migration (GAME_RULES §8)

- **Bots** occupy seats just like humans; on a bot's turn the Room waits
  `randf_range(0.8, 2.0)` s (`SceneTreeTimer`) then applies `BotPolicy.
  choose_move` (or auto-pass). Bot/human seats are interchangeable to the round
  loop.
- **Auto-pass (R1):** whenever the current seat (human or bot) has no legal move,
  the Room applies `pass` for it immediately — no client action needed.
- **Turn timer:** on `turn_started` set a deadline `now + TURN_TIMEOUT_SEC`. If
  the human doesn't `play_tile` by then, the Room auto-plays via `BotPolicy`
  (forced pass if stuck). **3 consecutive timeouts** convert that seat to a bot
  for the rest of the round (`player_replaced_by_bot`).
- **Disconnect during PLAYING:** mark the seat disconnected and let the bot loop
  drive it immediately (game never stalls); retain the hand server-side for
  reclaim. `player_replaced_by_bot` broadcast.
- **Reconnect:** `hello{session_token}` matching a disconnected seat in an active
  room reclaims it (`player_reclaimed`), resync per §7. Token = room-lifetime.
- **Host disconnect:** host role → longest-connected human; if no humans remain,
  destroy the room.
- **Room GC:** destroy rooms idle > 30 min or with no connected humans.

---

## 9. Shared pure logic (`core/round_view.gd`) — Step 0

The driver and the Room differ in the parts that need a `Node` — bot-delay
timers (`await`) and message *routing* (one local UI vs per-peer, redacted). Those
stay per-component. What they must **not** duplicate is the pure logic of turning
engine events into wire messages and computing scores; divergence there is the
local-vs-online desync ADR-003 exists to prevent.

Godot favors composition over deep inheritance, and this logic needs no Node, so
extract it into a `RefCounted` helper both components *call* (not subclass):

```gdscript
class_name RoundView          # core/round_view.gd — pure (ADR-003), unit-tested
extends RefCounted

## Enrich one engine event into a wire message. For round_over it also computes
## pip_counts + scores and accumulates them into the caller-owned `scoreboard`.
## `deadline_ms` is applied to turn_started only (-1 = none, e.g. local play).
static func to_wire(game: GapleGame, ev: Dictionary, scoreboard: Array, deadline_ms: int = -1) -> Dictionary

## The four round-start messages, ready to route (the caller decides who gets the
## private hands): { "broadcast": [game_started, public_state, turn_started],
##                   "hands": { seat: hand_msg, … } }
static func announce(game: GapleGame, deadline_ms: int = -1) -> Dictionary
```

- **`LocalGameDriver`** (Step 0 refactor): its `_to_wire`/`_announce_round`
  become calls to `RoundView`; seat 0's hand routes to the UI, others are bots.
- **`Room`**: calls the same `RoundView`; broadcasts the public messages and
  sends each human only its own `hands[seat]` (§7 redaction).

Do this first and keep Phase 2's 73 tests green (they pin the behavior). Add
`test_round_view.gd` for the helper directly. This is a *smaller* change to the
working driver than a base-class refactor, and leaves no second copy to drift.

---

## 10. Testability

- **`test_room.gd`** drives `Room` directly with a **fake `Transport`** that
  records `send`s; no sockets. Scenarios (each a rule): 2-human full round;
  1-human + 1-bot round (R2 minimum); join-while-PLAYING → `ROOM_IN_PROGRESS`
  (R3); host `end_game` aborts (no scores); disconnect → bot → reclaim; turn
  timeout auto-play; 3 timeouts → bot. Assert **no peer ever receives another
  seat's hand** (scan recorded sends).
- **Integration:** a headless GDScript WS client (`tools/ws_client.gd`) for a
  scripted two-client full round against a real `server_main` on localhost.
- Determinism: fixed seeds; `bot_delay`/timeouts overridable to 0 in tests
  (mirrors Phase 2's `bot_delay = Vector2.ZERO`).

---

## 11. Acceptance criteria (Phase 3 done = all green)

- ✅ Two script/`wscat` clients play a full round against the headless server,
  no Godot UI involved (proves protocol completeness).
- ✅ All `test_room.gd` scenarios green, including the **hidden-information**
  assertion (no cross-seat hand leakage).
- ✅ Joining an in-progress room returns `ROOM_IN_PROGRESS` (R3).
- ✅ A 1-human + 1-bot game completes (R2 minimum).
- ✅ Turn timeout auto-plays; 3 timeouts convert the seat to a bot.
- ✅ Disconnect → instant bot takeover; reconnect with token reclaims the seat
  mid-round.
- ✅ Phase 2's full suite still green (the shared orchestrator didn't regress it).

## 12. Task order & DAG

```
Step 0  core/round_view.gd (+test); refactor LocalGameDriver to call it (Phase 2 tests stay green)
Step 1  core/protocol.gd inbound parse/validate + test_protocol        (deps: none)
Step 2  server/transport.gd + session.gd + room_manager.gd + room.gd   (deps: 0,1)
        lobby + start + play loop + redaction + scoring; test_room.gd (basic)
Step 3  bots in Room + turn timer + timeout→autoplay + 3→bot           (deps: 2)
Step 4  disconnect→bot + reconnect via token                           (deps: 2,3)
Step 5  host migration / room destroy / GC                             (deps: 2,4)
Step 6  server/server_main.gd real WS transport + poll loop; wire main.gd (deps: 2)
Step 7  tools/ws_client.gd; two-client integration round + hidden-info check (deps: all)
Step 8  acceptance verification (§11)
```

Steps 0–5 are headless and fully unit-testable with the fake transport — build
and verify them before touching real sockets (Step 6).

## 13. Out of scope for Phase 3 (deferred)

Persistence across restarts (rooms die with the process — ADR-002), spectators,
chat, matchmaking/random pairing, a public room list, the match-target end
condition, TLS (Fly.io terminates it — Phase 5), and the networked *client* UI
(Phase 4 — this phase is verified with script clients only).
