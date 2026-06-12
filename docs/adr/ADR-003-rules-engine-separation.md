# ADR-003: Rules engine as a pure, engine-agnostic core module

- **Status:** Accepted
- **Date:** 2026-06-12
- **Deciders:** opan.mustopah

## Context

The game rules (`docs/GAME_RULES.md`) must behave identically on the
authoritative server and in the client (for move highlighting and optimistic
UI). Game logic mixed into Godot scene scripts is untestable, unportable, and
historically the main source of multiplayer desync bugs.

## Decision

All rules live in **`core/`** as plain `RefCounted` GDScript classes with these
hard constraints, enforced in code review:

1. **No scene-tree, rendering, networking, or input APIs** in `core/`. Allowed
   surface: language built-ins, `RefCounted`, math, `JSON`. No `Node`, no
   `get_tree()`, no signals to UI, no `await`.
2. **Deterministic:** all randomness flows through an injected
   `RandomNumberGenerator` with an explicit seed stored in `GameState`.
   Replaying the same seed + same intent sequence must reproduce the same state.
3. **Pure state machine API:** `GapleGame.apply(intent: Dictionary) ->
   ApplyResult` mutates state and returns the list of resulting events;
   `GapleGame.legal_moves(seat: int) -> Array[Move]` is side-effect free.
4. **Serializable:** `GameState.to_dict()` / `GameState.from_dict()` round-trip
   exactly; the server uses redacted views of this (`to_dict_for_seat(seat)`)
   to send hidden-information-safe snapshots.
5. **Unit-tested with GUT** (Godot Unit Test addon). Target: every rule in
   `GAME_RULES.md` §4–§7 has at least one test, including the blocked-game
   tie-breakers and the 5-tile deal (R4). CI runs tests headless.

The client renders **only from server events**; client-side `core/` usage is
limited to computing legal-move highlights from public state + own hand.

## Consequences

- (+) Rules are testable in milliseconds without booting scenes or sockets.
- (+) Zero server/client rules drift — same class, same code path.
- (+) If ADR-001's revisit trigger fires (port to TypeScript), `core/` is a
  mechanical port with the GUT test suite as the spec.
- (−) Slight ceremony: UI cannot "just check" a rule inline; it must call into
  `core/`. This is intended friction.
