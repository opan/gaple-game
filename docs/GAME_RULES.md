# Gaple — Game Rules Specification

This document is the single source of truth for game rules. The rules engine
(`core/`) must implement exactly what is written here. Anything ambiguous must be
resolved by editing this document first, then the code.

## 1. Origin and source requirements

Gaple is a traditional Indonesian domino game played with a standard double-six
domino set. The following requirements were captured from the design whiteboard
(`gaple.whiteboard`) and are **non-negotiable**:

- **R1.** The table has 4 seats. The local user always sits at the bottom (their
  hand is rendered as a fan — this is the user's PoV). The other 3 seats are
  either other human players or computer-simulated players (bots).
- **R2.** A game may mix real players and bots freely. It is impossible to play
  alone: the **minimum number of participants is 2** (the user plus at least one
  other player, human or bot).
- **R3.** Once a game starts, **no one can join mid-game**. Late arrivals must
  wait until the game ends — either by finishing naturally or by the host (the
  user who created the room) ending it manually.
- **R4.** At the start of a round, **each player is dealt exactly 7 tiles**
  (traditional Gaple). Keep the deal size as a single constant `HAND_SIZE = 7`
  so it can be made configurable later. (Historical note: an earlier whiteboard
  draft specified 5; the authoritative ruleset uses 7. With 4 players, 7×4 = 28
  consumes the entire set, so there is no boneyard at a full table.)
- **R5.** The game is based on the traditional Indonesian card/domino game named
  "Gaple".
- **R6.** **Unfair-hand redeal:** if, after dealing, any player holds **more
  than 5 balak** (doubles) — i.e. 6 or 7 of the 7 doubles — the round is
  considered unwinnable for the others and is **redealt** (reshuffle + deal
  again) until no player holds more than 5 doubles.

## 2. Equipment

- One **double-six domino set**: 28 unique tiles. Each tile has two ends with
  pip values from 0 to 6. The set is every unordered pair `(a, b)` with
  `0 <= a <= b <= 6`. Tiles where `a == b` are **doubles**.
- Canonical tile identity: a tile is stored as `(low, high)` with `low <= high`.
  Tile `(2,5)` and `(5,2)` are the same tile.

## 3. Setup

1. Player count `N` is 2, 3, or 4 (humans + bots combined, per R2).
2. Shuffle all 28 tiles with a seeded RNG (the seed is recorded for replay/audit).
3. Deal `HAND_SIZE = 7` tiles to each player, one at a time, clockwise starting
   from the seat after the dealer. Remaining tiles (`28 − 7N`) form the
   **boneyard** and are **never used** for the rest of the round (classic Gaple
   has no drawing). At a full 4-player table the boneyard is empty (`28 − 28`).
4. **Redeal check (R6):** if any player holds more than 5 doubles, discard the
   deal and repeat from step 2 with the next shuffle. Determinism is preserved
   by drawing each reshuffle from the same seeded RNG (so a given seed always
   yields the same final accepted deal).
5. Seats are ordered clockwise: seat 0 = bottom (user/host), seat 1 = right,
   seat 2 = top, seat 3 = left. With fewer than 4 players, unused seats are
   empty and skipped (see §8 seat mapping).

## 4. Determining the first player and first move

1. **Round 1:** the player holding the highest double (6|6, then 5|5, … 0|0)
   plays first and **must open with that double**. If no player holds any
   double, the player holding the tile with the highest pip sum opens with that
   tile (ties broken by higher `high` value, then by lowest seat index).
2. **Subsequent rounds (same room, "play again"):** the winner of the previous
   round opens and may play **any** tile from their hand.

## 5. Turn order and playing

1. Play proceeds **clockwise** (ascending seat index, wrapping, skipping empty
   seats).
2. The played tiles form a single **line** (the layout) with two open ends:
   `left_end` and `right_end` (pip values).
3. On their turn, a player must play one tile from their hand whose either side
   matches `left_end` or `right_end`. The tile is appended to that end and the
   open end value updates to the tile's other side.
4. If a tile can legally be played on **both** ends, the player chooses the end.
5. Doubles are placed on the line like any other tile (no spinners/branching —
   Gaple uses a single line only).
6. **Draw from boneyard:** if a player has no playable tile and the boneyard is
   not empty, they **must draw one tile at a time** until they draw a tile they
   can legally play (and must then play it on that same turn) or the boneyard
   is exhausted (then they pass). Drawing is forced and automatic — the engine
   handles it; a player may not pass voluntarily while the boneyard still has
   tiles. Each drawn tile is visible only to the drawing player.
7. **Pass:** if a player has no playable tile **and the boneyard is empty**,
   they must pass. Passing is forced and automatic. A player cannot pass
   voluntarily while holding a playable tile or while the boneyard is non-empty.
8. At a full 4-player table the boneyard starts empty (7×4 = 28), so rule 6
   never applies and behaviour is identical to classic no-draw Gaple.

## 6. Ending a round

A round ends in one of three ways:

1. **Domino (win by emptying hand):** a player plays their last tile. That
   player wins the round immediately.
2. **Blocked game (gapleh / locked):** every player passes consecutively (a full
   cycle of passes with no tile played). The winner is the player holding the
   **fewest tiles** in hand. Tie-breaks, in order:
   1. **Lowest balak-weighted value.** Sum the held tiles, where each non-double
      counts **1**, and each double (balak) counts **2** — *except* a player who
      also holds at least one tile with a **0** on either side counts every
      double as **1**. Lowest sum wins.
   2. **Clockwise-nearest.** If still tied, the tied player closest (clockwise)
      after the last player who placed a tile wins.
3. **Manual end (host action, per R3):** the host may end the game at any time.
   The round is **void** — no winner, no score is recorded — and the room
   returns to the lobby.

## 7. Scoring (per round, recorded on the room scoreboard)

- The winner scores 0. Every other player scores the **sum of pips remaining in
  their own hand** (penalty points, lower cumulative total is better).
- The room tracks cumulative scores across rounds until the room is closed.
- Optional match target (default **disabled**, constant `MATCH_TARGET = null`):
  when a player's cumulative penalty reaches the target (e.g. 100), the match
  ends and the player with the lowest total wins the match.

## 8. Seats, lobby, and lifecycle rules

- **Room lifecycle:** `LOBBY → PLAYING → ROUND_OVER → (LOBBY | PLAYING)`.
- The **host** is the user who created the room. The host can: add/remove bots,
  kick humans (lobby only), start the game (only when `N >= 2`), end the game
  manually (PLAYING only), and start the next round (ROUND_OVER).
- Joining is allowed **only** in `LOBBY` state (R3). A join attempt during
  `PLAYING` receives an explicit `ROOM_IN_PROGRESS` error and may watch the
  room card show "in progress" in the room list, but cannot spectate v1.
- **Disconnects during PLAYING:** the disconnected human's seat is taken over by
  a bot immediately (the game never stalls). If the human reconnects before the
  round ends, they reclaim their seat. If the **host** disconnects, host role
  transfers to the longest-connected human; if no humans remain, the room is
  destroyed.
- **Turn timer:** 30 seconds per turn (constant `TURN_TIMEOUT_SEC = 30`). On
  timeout the engine auto-plays for the player: forced pass if no legal move,
  otherwise the bot policy picks the move. Three consecutive timeouts convert
  the seat to a bot for the rest of the round.

### Seat mapping (rendering, from the whiteboard)

The local client always renders **itself at the bottom**. Other players are laid
out clockwise relative to the local player's seat index:

| N players | Relative offsets → screen positions |
|---|---|
| 2 | +1 → top |
| 3 | +1 → right, +2 → left |
| 4 | +1 → right, +2 → top, +3 → left |

Opponents' tiles are rendered face-down (card backs): top seat vertical, left
and right seats rotated 90° (horizontal), matching the whiteboard sketch.

## 9. Glossary

| Term | Meaning |
|---|---|
| Tile / card | One domino piece `(low, high)` |
| Double / balak | Tile with equal ends, e.g. 6\|6 ("balak enam") |
| Layout / line | The chain of played tiles on the table |
| Open end | One of the two pip values playable at the ends of the line |
| Boneyard | Undealt tiles; unused in Gaple |
| Blocked / locked | No player can move; round decided by pip count |
| Gaple | Both the game name and the blocked-game condition in Indonesian usage |
