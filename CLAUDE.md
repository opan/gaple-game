# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this project is

A web-based multiplayer **Gaple** game (traditional Indonesian double-six
dominoes), built with **Godot 4.6.3 / GDScript**, exported to the browser, with
an authoritative headless Godot server. 2–4 players per room, humans and bots
mixed freely.

**Current state: Phases 0–3 done.** Project bootstrap; the pure `core/` rules
engine (`tile`, `domino_set`, `game_state`, `gaple_game`, `protocol`,
`bot_policy`, `round_view`); the local single-player game in `client/`
(`local_game_driver` + `scenes/`); and the authoritative multiplayer server in
`server/` (`server_main`, `game_server`, `room`, `transport`/`ws_transport`).
Full GUT suite (100 tests, incl. a real-socket integration test) plus a 10k-round
fuzz harness. Next is Phase 4 (networked client). Implementation follows `PLAN.md`
in order; each phase's acceptance criteria must pass before the next.

Per-phase detail: `docs/PHASE_2_PLAN.md`, `docs/PHASE_3_PLAN.md`. Load-bearing
seams: the UI renders only from wire messages (Phase 4 swaps `LocalGameDriver`
for a network connection unchanged); `core/protocol.gd` is the shared wire
contract (outbound builders + inbound parse/validate); `core/round_view.gd` holds
the event→wire + scoring logic shared by the driver and the server `Room` so they
can't drift. Server transport is **raw WebSockets** (`TCPServer` +
`WebSocketPeer.accept_stream`), not `WebSocketMultiplayerPeer` (which corrupts
JSON for browser clients). JSON numbers arrive as floats — always `int(...)`.

## Document hierarchy (read before writing code)

Precedence on rules questions: `docs/GAME_RULES.md` > `PLAN.md` > your judgment.
If the rules doc is ambiguous, fix the doc first, then the code.

- `docs/GAME_RULES.md` — exact game rules the engine implements, including the
  whiteboard requirements R1–R5 (4-seat table, min 2 players, no mid-game
  joins, 5-tile deal, host can end manually). Tie-breakers, scoring, seat
  mapping, and lifecycle are all specified here.
- `PLAN.md` — phased implementation plan: repo layout, core class signatures
  (§2), the full client↔server JSON protocol (§6), UI layout spec (§7.1),
  required unit tests, acceptance criteria per phase.
- `docs/adr/ADR-001…005` — engine choice, multiplayer architecture, rules
  engine separation, bot AI, deployment. Don't contradict an ADR silently; if
  a decision must change, update the ADR.

## Architecture (the parts that span multiple files)

- **Single Godot project, three roles.** `main.gd` bootstraps: with `--server`
  in user args it runs the headless WebSocket server (`server/`); otherwise the
  client UI (`client/`). Bots run inside the server process.
- **`core/` is a pure rules engine (ADR-003) — the load-bearing constraint.**
  Plain `RefCounted` classes only: no `Node`, no scene tree, no networking, no
  UI, no `await`. All randomness through an injected seeded
  `RandomNumberGenerator`. Both server and client use the same `core/` code, so
  rules can never drift between them. UI must call into `core/` for legality
  checks, never re-implement a rule inline.
- **Server is authoritative (ADR-002).** Clients send intents
  (`play_tile`, `pass`…); the server validates via `GapleGame.apply()` and
  broadcasts events. Hidden information never leaves the server: a client gets
  its own hand and only tile *counts* for opponents. The wire format is JSON
  over WebSocket, schema in `PLAN.md` §6; every message carries protocol
  version `v`.
- **Client UI is driver-agnostic.** Phase 2 builds the game against a
  `LocalGameDriver` (wraps `GapleGame` + bots locally); Phase 4 swaps in the
  network connection emitting the same protocol-shaped event dictionaries. UI
  renders from events, never from direct engine state.
- **Tiles on the wire are integer ids 0..27** (canonical ordering defined in
  `PLAN.md` §2.1). A tile is always stored normalized as `(low, high)`.
- **Key constants live in `core/game_state.gd`:** `HAND_SIZE = 5` (whiteboard
  requirement — traditional Gaple uses 7; never hardcode the deal size
  elsewhere), `TURN_TIMEOUT_SEC = 30`.

## Conventions

- Typed GDScript (`var x: int`, `-> ReturnType`) is **mandatory** in `core/`
  and `server/`, encouraged elsewhere.
- Every rule in `docs/GAME_RULES.md` §4–§7 must have a GUT unit test; the
  required test inventory is in `PLAN.md` §4.
- Every commit must keep the GUT suite green.

## Commands (once Phase 0 lands)

Godot version is pinned to 4.6.3 — keep CI image and Dockerfile in sync.

```sh
# Run all unit tests (headless). Test dirs are configured in .gutconfig.json.
# Exit code is 0 on all-pass, 1 on any failure (verified — CI relies on this).
godot --headless -s addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json

# Run a single test script
godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_rules.gd -gexit

# Run the game server (Ctrl-C to stop)
godot --headless -- --server --port=9000

# Run the client: open the project in the Godot editor and press F5
```

The `godot` binary is the Godot 4.6.3 app; on this machine it is symlinked to
`/opt/homebrew/bin/godot` → `/Applications/Godot.app/Contents/MacOS/Godot`.
