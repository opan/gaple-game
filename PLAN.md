# Gaple — Implementation Plan

A web-based multiplayer Gaple (Indonesian dominoes) game built with **Godot 4.6
(GDScript)**, exported to the browser, with an authoritative headless Godot
server, 2–4 players per room, and free mixing of humans and bots.

This plan is written to be executed phase-by-phase by an engineer or coding
agent **without further clarification**. Read these first:

| Document | Purpose |
|---|---|
| `docs/GAME_RULES.md` | Exact game rules — the spec the rules engine implements |
| `docs/adr/ADR-001-game-engine.md` | Why Godot 4 + Web export (and the considered alternative) |
| `docs/adr/ADR-002-multiplayer-architecture.md` | Authoritative server, WebSocket, JSON protocol |
| `docs/adr/ADR-003-rules-engine-separation.md` | Pure `core/` module constraints |
| `docs/adr/ADR-004-bot-ai.md` | Bot policy design |
| `docs/adr/ADR-005-deployment.md` | Hosting and CI/CD |

**Ground rules for whoever executes this plan**

1. `docs/GAME_RULES.md` outranks this plan; this plan outranks your judgment on
   rules questions. If the rules doc is ambiguous, fix the doc first.
2. Do the phases in order. Each phase ends with all its acceptance criteria
   (✅ boxes) passing. Do not start phase N+1 with a red criterion in phase N.
3. Typed GDScript (`var x: int`, `-> ReturnType`) is mandatory in `core/` and
   `server/`, encouraged elsewhere.
4. Every commit must keep `godot --headless -s addons/gut/gut_cmdln.gd` green.

---

## 1. Final repository layout

```
gaple-game/
├── PLAN.md
├── README.md                      # how to run client/server/tests locally
├── project.godot                  # single Godot 4.6 project
├── export_presets.cfg             # Web export preset
├── main.gd / main.tscn            # bootstrap: --server → headless server, else client UI
├── core/                          # PURE rules engine (ADR-003) — no Node, no net, no UI
│   ├── tile.gd                    # Tile value type
│   ├── domino_set.gd              # 28-tile set generation + seeded shuffle/deal
│   ├── game_state.gd              # full round state + (de)serialization + redacted views
│   ├── gaple_game.gd              # state machine: apply(intent) -> events, legal_moves()
│   ├── bot_policy.gd              # ADR-004 Greedy+ policy
│   └── protocol.gd                # message type constants + validation helpers
├── server/
│   ├── server_main.gd             # WebSocket listener, connection lifecycle
│   ├── room_manager.gd            # room codes, create/join/destroy
│   ├── room.gd                    # lobby + game orchestration, timers, bots, scoring
│   └── session.gd                 # peer_id ↔ session_token ↔ seat binding
├── client/
│   ├── net/
│   │   ├── config.gd              # server URL per build type (ADR-005)
│   │   └── connection.gd          # autoload: WebSocket client, send/receive, reconnect
│   ├── scenes/
│   │   ├── main_menu.tscn/.gd     # name entry, create room / join by code
│   │   ├── lobby.tscn/.gd         # seat list, add/remove bot, start button (host)
│   │   ├── game_table.tscn/.gd    # the whiteboard layout (see §7)
│   │   ├── hand.tscn/.gd          # bottom fan of the local player's tiles
│   │   ├── tile_node.tscn/.gd     # one rendered domino (face or back)
│   │   ├── opponent_seat.tscn/.gd # name + face-down tile count (top/left/right)
│   │   ├── board_line.tscn/.gd    # the played-tile chain with two drop zones
│   │   └── round_over.tscn/.gd    # results, scoreboard, play-again (host)
│   └── theme/                     # one Theme resource, fonts, colors
├── assets/
│   └── tiles/                     # generated tile atlas (see §7.1) + card back
├── tests/
│   └── unit/                      # GUT tests: test_tile.gd, test_deal.gd,
│                                  # test_rules.gd, test_blocked.gd, test_bot.gd,
│                                  # test_protocol.gd, test_room.gd
├── addons/gut/                    # GUT test addon (committed)
├── deploy/
│   ├── Dockerfile                 # headless server image (ADR-005)
│   ├── fly.toml
│   └── pages_headers              # Cloudflare _headers file (COOP/COEP)
└── .github/workflows/ci.yml      # tests + web export + deploy (ADR-005)
```

---

## 2. Core data model (Phase 1 deliverable)

### 2.1 `core/tile.gd` — `class_name Tile extends RefCounted`

```gdscript
var low: int    # 0..6
var high: int   # 0..6, invariant low <= high (normalize in _init)
func pips() -> int                  # low + high
func is_double() -> bool            # low == high
func matches(end: int) -> bool      # low == end or high == end
func other_side(end: int) -> int    # the value left open after playing onto `end`
func to_id() -> int                 # canonical 0..27 index for wire format
static func from_id(id: int) -> Tile
func equals(t: Tile) -> bool
```

Wire format for a tile is always its integer `id` (0..27), ordering: (0,0)=0,
(0,1)=1 … (0,6)=6, (1,1)=7, … (6,6)=27.

### 2.2 `core/game_state.gd` — `class_name GameState`

```gdscript
const HAND_SIZE := 7            # R4 — single source of truth for deal size
const TURN_TIMEOUT_SEC := 30

var seed: int                   # RNG seed used for this round (replayable)
var num_players: int            # 2..4
var hands: Array[Array]         # hands[seat] = Array[Tile]
var line: Array[Tile]           # played chain, index 0 = left end
var left_end: int               # -1 before first tile
var right_end: int
var current_seat: int
var consecutive_passes: int
var phase: int                  # enum: DEALT, PLAYING, ROUND_OVER
var winner_seat: int            # -1 until ROUND_OVER
var end_reason: int             # enum: DOMINO, BLOCKED, ABORTED
var last_placer_seat: int       # for blocked tie-break (GAME_RULES §6.2)
var opening_move: Dictionary    # forced first tile info (GAME_RULES §4)

func to_dict() -> Dictionary                    # full state (server-side only)
static func from_dict(d: Dictionary) -> GameState
func public_dict() -> Dictionary                # line, ends, current_seat,
                                                # per-seat tile COUNTS, phase
func hand_dict(seat: int) -> Array              # that seat's tile ids only
```

### 2.3 `core/gaple_game.gd` — `class_name GapleGame`

```gdscript
static func new_round(num_players: int, seed: int, opener_override: int = -1) -> GapleGame
    # shuffles, deals HAND_SIZE each, computes forced opener per GAME_RULES §4

var state: GameState

func legal_moves(seat: int) -> Array[Dictionary]
    # each move: { "tile_id": int, "end": "L"|"R" }
    # empty array ⇒ that seat must pass

func apply(intent: Dictionary) -> Dictionary
    # intent: { "type": "play", "seat": int, "tile_id": int, "end": "L"|"R" }
    #      or { "type": "pass", "seat": int }   (server-initiated, forced only)
    #      or { "type": "abort", "seat": int }  (host manual end, GAME_RULES §6.3)
    # returns { "ok": bool, "error": String, "events": Array[Dictionary] }
    # events (in order produced): tile_played, player_passed, turn_started,
    #                             round_over
    # MUST reject: wrong seat's turn, tile not in hand, tile not matching end,
    #              pass while a legal move exists, any intent when ROUND_OVER.

func pip_count(seat: int) -> int
static func blocked_winner(state: GameState) -> int   # GAME_RULES §6.2 incl. tie-breaks
```

### 2.4 Scoring helper (used by `Room`)

`round_scores(state) -> Array[int]`: winner 0, others their own `pip_count`
(GAME_RULES §7). Aborted rounds produce no scores.

---

## 3. Phase 0 — Project bootstrap (≈ half a day)

Tasks:

1. Install Godot **4.6.3 stable**; record the exact version in `README.md` and
   pin it everywhere (CI image, Dockerfile).
2. `project.godot`: project name "Gaple", main scene `main.tscn`, viewport
   1280×720, stretch mode `canvas_items`, aspect `expand` (works portrait-ish
   and landscape in browsers).
3. Add **GUT** addon under `addons/gut/`, commit it, enable plugin.
4. `main.gd`: parse `OS.get_cmdline_user_args()`; if `--server` present, load
   server entry (Phase 3) else show `main_menu.tscn`. Until those exist, print
   a placeholder line for each branch.
5. `.gitignore` (Godot template: `.godot/`, `*.translation`, export artifacts).
6. `README.md`: run client (editor F5), run server
   (`godot --headless -- --server --port=9000`), run tests
   (`godot --headless -s addons/gut/gut_cmdln.gd -gdir=tests/unit -gexit`).
7. CI workflow running the test command in a pinned Godot container.

Acceptance criteria:
- ✅ `godot --headless -- --server` prints the server placeholder and exits clean on SIGINT.
- ✅ Empty GUT suite runs green locally and in CI.

## 4. Phase 1 — Rules engine `core/` (≈ 2–3 days) — **the foundation**

Implement §2 exactly. No Godot `Node` usage anywhere in `core/` (ADR-003).

Required unit tests (minimum set; one test file per area):

| Test | Asserts |
|---|---|
| `test_tile.gd` | normalization (5,2)→(2,5); `to_id`/`from_id` round-trip for all 28; `matches`/`other_side` |
| `test_deal.gd` | 28 unique tiles; deal gives `HAND_SIZE`=7 each for N=2,3,4; boneyard = 28−7N; no hand >5 doubles (R6 redeal); same seed ⇒ same deal; different seed ⇒ different deal |
| `test_opening.gd` | highest double opens and the opening tile is forced; no-doubles fallback (highest pip sum, documented tie-breaks) |
| `test_rules.gd` | legal_moves correctness on both ends; double-end choice honored; reject: out-of-turn, tile-not-in-hand, non-matching end, voluntary pass with legal move available; turn advances clockwise skipping nothing (2,3,4 players) |
| `test_end.gd` | win by last tile fires `round_over{reason:DOMINO}`; full pass cycle fires `round_over{reason:BLOCKED}` |
| `test_blocked.gd` | blocked (gapleh) winner = fewest tiles; balak-weighted-value and clockwise tie-breakers from GAME_RULES §6.2 with hand-constructed fixtures |
| `test_scoring.gd` | winner 0, others own pips; abort produces no scores |
| `test_serialization.gd` | `to_dict`/`from_dict` round-trip equality mid-game; `public_dict` contains **no** hand contents, only counts; `hand_dict(s)` only seat s |
| `test_bot.gd` | (Phase 2) policy priorities: winning move > double > highest pips; bot never returns an illegal move over 1000 random seeded games |
| `test_replay.gd` | same seed + same intent log replayed ⇒ identical final `to_dict()` |

Acceptance criteria:
- ✅ All tests above exist and pass.
- ✅ A scripted headless "random legal playout" of 10,000 rounds (all seat
  counts) completes with zero engine errors and every round reaching
  `ROUND_OVER` (this becomes `test_fuzz.gd`, kept in CI with 500 rounds).

## 5. Phase 2 — Local single-player game (≈ 3–4 days)

> **Detailed, executable spec: `docs/PHASE_2_PLAN.md`.** It supersedes this
> section where they differ and records four reviewed refinements: (R1) build
> `core/protocol.gd` first; (R2) `LocalGameDriver` extends `Node` (timer access),
> not `RefCounted`; (R3) tiles are drawn at runtime via `TileFace._draw()` rather
> than a build-time atlas; (R4) the driver enriches `turn_started`/`round_over`
> with data the pure engine lacks (deadline, pip_counts, scores, scoreboard).

Goal: the user plays a full offline round against 1–3 bots with the whiteboard
UI, **before any networking exists**. The client talks to a `LocalGameDriver`
that has the same surface as the future network connection (emits the same
wire messages from §6), so Phase 4 swaps the driver, not the UI.

Tasks (see `docs/PHASE_2_PLAN.md` §3–§12 for the detail and task DAG):

0. `core/protocol.gd` — message types, version, builders, engine-event → wire
   translation, with `test_protocol.gd`. (Shared with Phase 3.)
1. `core/bot_policy.gd` per ADR-004, with `test_bot.gd`.
2. `LocalGameDriver` (`extends Node`): wraps `GapleGame` + bot policies + bot
   delay timers, emits wire messages via `event_received(msg)`; with
   `test_local_driver.gd`.
3. `tile_face.gd` (runtime `_draw()`), `tile_node.tscn`, then `board_line.tscn`,
   `hand.tscn` fan, `opponent_seat.tscn`.
4. `game_table.tscn` per §7 layout + interaction state machine: tap a hand tile
   → legal end(s) glow; both-ends ⇒ user picks; illegal tiles desaturated and
   non-interactive (from `legal_moves`).
5. Forced pass: banner "No playable tile — passing…" (1.5 s) then auto-pass.
6. Turn indicator, opponent count decrement animation, played tile flies to the
   line end (Tween, ~0.25 s).
7. `round_over.tscn`: winner, reason (domino/blocked), pip table, cumulative
   scoreboard, play again.
8. A "Practice vs bots" menu hook that configures 1–3 bots (N = 2–4).

Acceptance criteria:
- ✅ Full round vs 3 bots is playable start→finish with mouse only.
- ✅ Blocked game reachable and shows the correct pip-count winner.
- ✅ UI never permits an illegal move (verified by trying: wrong turn, wrong
  tile, wrong end).
- ✅ Runs in the browser via a local Web export (`python -m http.server` with a
  COOP/COEP-injecting script or godot's editor "Remote Debug → Run in browser").

## 6. Phase 3 — Server + protocol (≈ 3–4 days)

> **Detailed, executable spec: `docs/PHASE_3_PLAN.md`.** It supersedes this
> section where they differ and records six reviewed refinements: (R1) the server
> **auto-passes** a stuck seat — clients never send `pass`; (R2) add **inbound
> parse/validation** to `core/protocol.gd`; (R3) Room/RoomManager take an
> **injected transport sink** so the whole thing is unit-testable without
> sockets; (R4) extract the shared *pure* event→wire/scoring logic into
> **`core/round_view.gd`** that both the Phase 2 driver and the Room call
> (composition, not a base class) so they can't drift; (R5) **contiguous logical
> seats**, host = seat 0;
> (R6) single-threaded **poll loop**, no locks.

Implement `server/` per ADR-002. **Wire protocol** (all messages JSON, field
`t` = type, `v` = protocol version `1`):

Client → Server:

| `t` | payload | notes |
|---|---|---|
| `hello` | `name`, `v`, `session_token?` | first message; token reclaims seat |
| `create_room` | — | replies `room_state`, sender becomes host, seat 0 |
| `join_room` | `code` | errors: `ROOM_NOT_FOUND`, `ROOM_FULL`, `ROOM_IN_PROGRESS` (R3) |
| `add_bot` / `remove_bot` | `seat?` | host only, lobby only |
| `start_game` | — | host only, requires ≥2 occupied seats (R2) |
| `play_tile` | `tile_id`, `end` ("L"/"R") | validated by `GapleGame.apply` |
| `end_game` | — | host only → abort per GAME_RULES §6.3 |
| `play_again` | — | host only, from ROUND_OVER |
| `leave_room` | — | lobby: frees seat; in game: seat becomes bot |

Server → Client:

| `t` | payload |
|---|---|
| `welcome` | `session_token`, `v` |
| `room_state` | code, host seat, seats: `[{seat, name, kind: human/bot/empty, connected}]`, phase, scoreboard |
| `game_started` | `num_players`, `opener_seat`, `opening_tile_id?` |
| `hand` | `tile_ids` (recipient's hand only — never broadcast) |
| `public_state` | output of `GameState.public_dict()` (sent on start and on reconnect) |
| `tile_played` | `seat`, `tile_id`, `end`, `new_left_end`, `new_right_end`, `remaining_count` |
| `player_passed` | `seat` |
| `turn_started` | `seat`, `deadline_unix_ms` |
| `round_over` | `reason`, `winner_seat`, `pip_counts[]`, `scores[]`, scoreboard |
| `player_replaced_by_bot` / `player_reclaimed` | `seat` |
| `error` | `code`, `message` (codes: `BAD_INTENT`, `NOT_YOUR_TURN`, `ILLEGAL_MOVE`, `NOT_HOST`, `ROOM_NOT_FOUND`, `ROOM_FULL`, `ROOM_IN_PROGRESS`, `UPDATE_REQUIRED`) |

Server behaviors to implement (each maps to a rule):

1. Validation-first: every client intent goes through `protocol.gd` shape
   validation, then room-phase checks, then `GapleGame.apply`. Any failure →
   `error`, no state change, no broadcast.
2. Turn timer per `TURN_TIMEOUT_SEC` → autoplay via bot policy; 3 consecutive
   timeouts → `player_replaced_by_bot` (GAME_RULES §8).
3. Disconnect during PLAYING → instant bot takeover + token-based reclaim.
4. Host disconnect → host migration / room destruction per GAME_RULES §8.
5. Bots act with 0.8–2.0 s humanized delay (ADR-004).
6. Room codes: 5 chars from `ABCDEFGHJKLMNPQRSTUVWXYZ23456789` (no 0/O/1/I).
7. Room GC: destroy rooms idle > 30 min or empty of humans.

Testing: `test_room.gd` drives `Room` directly with fake peer ids (no real
sockets): full 2-human game, human+bot game, join-while-playing rejected,
host-end aborts, disconnect→bot→reclaim, timeout autoplay.

Acceptance criteria:
- ✅ Two `wscat`/script clients can play a full round against the headless
  server with no Godot client involved (proves protocol completeness).
- ✅ All `test_room.gd` scenarios green.
- ✅ Joining an in-progress room returns `ROOM_IN_PROGRESS` (whiteboard R3).
- ✅ Game with 1 human + 1 bot works (whiteboard R2 minimum).

## 7. Phase 4 — Networked client (≈ 3–4 days)

> **Detailed, executable spec: `docs/PHASE_4_PLAN.md`.** It supersedes this
> section where they differ and records the reviewed refinements: (R1) the client
> computes its own legal-move highlights via a new pure **`core/legal.gd`** (server
> stays authoritative); (R2) the local driver is aligned to **auto-pass** stuck
> seats like the server, so the client never sends `pass`; (R3) the client learns
> its seat from the `hand` message; (R4) `game_table` takes an injected
> **`GameClient`** (local driver *or* network connection) — one UI, two sources;
> (R5) a raw-`WebSocketPeer` **`NetworkConnection`** autoload with token reconnect;
> (R6) reconnect reuses the server's resync messages.

1. `connection.gd` autoload: connect/handshake (`hello`→`welcome`), send
   helpers, signal `event_received(msg)`, auto-reconnect with stored
   `session_token` (3 retries, exponential backoff), connection-lost overlay.
2. `main_menu.tscn`: player name (persisted via `ConfigFile` in `user://`),
   buttons: **Practice vs bots** (Phase 2 local driver), **Create room**,
   **Join room** (code entry).
3. `lobby.tscn`: 4 seat slots showing name/kind; host controls: add/remove
   bot, kick, Start (enabled only when ≥2 seats occupied); non-hosts see
   "waiting for host"; room code displayed large for sharing.
4. `game_table.gd`: consume the same events as Phase 2 (only the driver
   changes); add: turn countdown ring on active seat (from `deadline_unix_ms`),
   "bot took over seat" toast, host-only **End game** button with confirm
   dialog (→ `end_game`).
5. `round_over.tscn`: cumulative room scoreboard; host gets **Play again**,
   others "waiting for host".
6. Reconnect flow: refreshing the browser tab mid-game and rejoining with the
   token restores hand + `public_state` and continues play.

### 7.1 Visual layout (from the whiteboard) and tile art

```
                 [ opponent: TOP ]            ← vertical face-down stack + name
                                              + tile count
 [opp: LEFT]      ┌──────────────┐      [opp: RIGHT]
 (rotated 90°)    │  board line  │      (rotated 90°)
                  │  of played   │
                  │  tiles, two  │
                  │  glowing     │
                  │  drop ends   │
                  └──────────────┘
              ╭─ fanned hand of the user ─╮   ← bottom, PoV per whiteboard;
                 7 tiles, arc fan, hover      always the local player
                 raises a tile slightly
```

- Seat→position mapping per `GAME_RULES.md` §8 table (2P: opponent on top;
  3P: right+left; 4P: right+top+left).
- Tile art: **generate programmatically** — rounded rectangle, divider line,
  pip dots via a small `tool` script that renders all 28 faces + 1 back into an
  atlas at build time (keeps the web bundle tiny per ADR-001). Pip layouts are
  the standard dice patterns for 0–6.
- Hand fan: tiles arranged on an arc (rotation `lerp(-18°, 18°)` across the
  hand), hover/focus lifts the tile 16 px (matches the whiteboard sketch).
- The board line auto-scales/wraps: render the chain as a `Line of TileNodes`
  inside a `CenterContainer`; when wider than 70 % of viewport, scale down
  (min 0.5) — 20 played tiles max (5×4) always fits.

Acceptance criteria:
- ✅ Two browsers (one normal, one incognito) play a full game on localhost.
- ✅ Host adds a bot, 2 humans + 1 bot finish a round; scores correct.
- ✅ Mid-game tab refresh reclaims the seat and play continues.
- ✅ Host "End game" returns everyone to the lobby, no scores recorded.
- ✅ Late joiner gets `ROOM_IN_PROGRESS` toast and stays on the menu.

## 8. Phase 5 — Deployment (≈ 1–2 days)

Per ADR-005: `deploy/Dockerfile` + `fly.toml` for the server; Cloudflare Pages
(+ `_headers` for COOP/COEP) for the client; CI pipeline test → export →
deploy; protocol version check returns `UPDATE_REQUIRED` to stale clients.

Acceptance criteria:
- ✅ Public URL loads the game; two devices on different networks finish a game
  over `wss://`.
- ✅ CI deploys on merge to `main`; a deliberately wrong `v` in a test client
  receives `UPDATE_REQUIRED`.

## 9. Phase 6 — Polish (≈ 2–3 days, ship-blocking items only)

1. SFX: deal, place, pass, win, lose (CC0 sounds, e.g. Kenney audio packs);
   mute toggle persisted.
2. Animations: deal-in stagger, opponent play (back flies → flips at line),
   win confetti `CPUParticles2D`, blocked-game "LOCKED" stamp.
3. Mobile browser pass: touch targets ≥ 44 px, test portrait + landscape on one
   iOS Safari and one Android Chrome device; loading screen with progress bar
   (Godot's web shell customization) given the wasm download size.
4. Quality pass: error toasts for all `error` codes, empty-name guard, prevent
   double-click double-send (disable input until server event echoes back).
5. README/itch page screenshots.

Acceptance criteria:
- ✅ Playable comfortably on a mid-range phone browser.
- ✅ No unhandled `error` code paths (grep protocol codes vs toast handler).

## 10. Out of scope for v1 (recorded so nobody "helpfully" adds them)

Accounts/auth, persistence of rooms across restarts, spectators, chat,
matchmaking (random pairing), 7-tile traditional variant (kept behind the
`HAND_SIZE` constant), rankings/leaderboards, native mobile builds, `hard` bot.

## 11. Estimated timeline

| Phase | Effort |
|---|---|
| 0 Bootstrap | 0.5 d |
| 1 Rules engine | 2–3 d |
| 2 Local single-player | 3–4 d |
| 3 Server + protocol | 3–4 d |
| 4 Networked client | 3–4 d |
| 5 Deployment | 1–2 d |
| 6 Polish | 2–3 d |
| **Total** | **≈ 15–20 working days** |

Phases 2 and 3 can run in parallel (different people/agents) after Phase 1 —
they share only `core/` and the protocol table in §6.
