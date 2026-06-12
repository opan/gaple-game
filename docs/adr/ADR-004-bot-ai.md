# ADR-004: Bot AI — server-side heuristic policy behind a seat interface

- **Status:** Accepted
- **Date:** 2026-06-12
- **Deciders:** opan.mustopah

## Context

The whiteboard requires (R1/R2): any of the 3 non-user seats may be a computer,
mixed freely with humans, minimum 2 participants total. Additionally
(`GAME_RULES.md` §8) bots take over disconnected/timed-out humans mid-round, so
a bot must be able to start from *any* mid-game state.

Options: (a) heuristic rule-based policy, (b) Monte-Carlo simulation with
hidden-hand sampling, (c) ML model. Gaple with 5-tile hands has a tiny decision
space (usually 0–3 legal moves), so (a) reaches credible play; (b)/(c) are
over-engineering for v1.

## Decision

1. **Interface:** `core/bot_policy.gd` exposes
   `choose_move(public_state: Dictionary, hand: Array, legal: Array[Move]) -> Move`.
   The bot sees exactly what a human in that seat sees (own hand + public
   state) — no hidden-information access, by construction.
2. **Placement:** bots run **inside the server process**. `Room` calls the
   policy when the current seat is bot-occupied, after a humanizing delay of
   `randf_range(0.8, 2.0)` seconds.
3. **v1 policy — "Greedy+", in priority order:**
   1. If a move wins the round (last tile), play it.
   2. Prefer dumping **doubles** (they are the riskiest to be stuck with).
   3. Otherwise play the tile with the **highest pip sum** (minimizes blocked-game
      penalty per GAME_RULES §7).
   4. Tie-break: prefer the move that keeps the most distinct pip values in
      hand (flexibility); then random via the room's seeded RNG.
4. **Difficulty hook (v1 ships "normal" only):** `BotPolicy.new(difficulty)`
   where `easy` = uniform random legal move, `normal` = Greedy+ above, `hard` =
   reserved for a future sampling policy.

## Consequences

- (+) Bots, disconnect stand-ins, and turn-timeout autoplay are all the same
  code path; the room logic is seat-occupant-agnostic.
- (+) Policy is in `core/`, unit-testable (fixed seeds, asserted choices).
- (−) Greedy+ is exploitable by strong players (no end-counting/blocking
  strategy); acceptable for v1, slot reserved for `hard`.
