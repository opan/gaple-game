# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this project is

A web-based multiplayer **Gaple** game (traditional Indonesian double-six
dominoes), built with **Godot 4.4 / GDScript**, exported to the browser, with
an authoritative headless Godot server. 2–4 players per room, humans and bots
mixed freely.

**Current state: planning phase — no code exists yet.** The repo contains the
complete plan and decision records. Implementation follows the phases in
`PLAN.md`, in order; each phase has acceptance criteria that must pass before
the next phase starts.

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

Godot version is pinned to 4.4.x — keep CI image and Dockerfile in sync.

```sh
# Run all unit tests (headless)
godot --headless -s addons/gut/gut_cmdln.gd -gdir=tests/unit -gexit

# Run a single test script
godot --headless -s addons/gut/gut_cmdln.gd -gtest=tests/unit/test_rules.gd -gexit

# Run the game server
godot --headless -- --server --port=9000

# Run the client: open the project in the Godot editor and press F5
```
