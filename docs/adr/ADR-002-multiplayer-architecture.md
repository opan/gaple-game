# ADR-002: Multiplayer architecture — authoritative headless Godot server over WebSocket

- **Status:** Accepted
- **Date:** 2026-06-12
- **Deciders:** opan.mustopah

## Context

Requirements from `docs/GAME_RULES.md`: 2–4 players per room, free mix of
humans and bots, no mid-game joins, host can end a game manually, disconnected
humans are replaced by bots so games never stall. The client runs in a browser
(Godot Web export), which restricts transports to **WebSocket** and **WebRTC**.

Options:

1. **Authoritative dedicated server** — a headless Godot instance owns all
   game state; clients send intents, server validates and broadcasts results.
2. **Peer-to-peer (WebRTC) with host migration** — one player's browser is
   authoritative.
3. **Backend-as-a-service relay (Nakama, Colyseus, Firebase)** — third-party
   server runtime; game rules would live in Go/TS, not GDScript.

P2P is rejected: trivial to cheat (host sees all hands), host disconnect is
catastrophic, and WebRTC signaling still needs a server anyway. BaaS is
rejected because it splits the rules engine into a second language, violating
the single-codebase benefit from ADR-001.

## Decision

**Option 1: authoritative dedicated server**, implemented as the *same Godot
project* run headless:

- `godot --headless -- --server --port=9000` boots `server/server_main.gd`
  (selected via a `Main` bootstrap autoload that inspects CLI args).
- Transport: **WebSocketServer (WSS in production)** using Godot's
  `WebSocketMultiplayerPeer` in *raw packet* mode — we do **not** use Godot's
  high-level RPC/scene replication, because the server has no scene tree for
  game objects and we want an inspectable, versioned protocol.
- Protocol: **JSON messages** (one JSON object per WebSocket text frame), schema
  defined in `core/protocol.gd` and documented in `PLAN.md` §6. Every message
  has `{ "t": "<type>", "v": 1, ...payload }`.
- **Hidden information stays server-side:** clients receive their own hand in
  full, and only *tile counts* for opponents. Played tiles are public. A client
  can therefore not cheat by reading memory/traffic.
- **Client sends intents only** (`play_tile`, `pass_ack`, `start_game`, …); the
  server validates every intent against the rules engine and broadcasts
  authoritative events. An illegal intent gets an `error` message and no state
  change.
- **Rooms:** in-memory `RoomManager` holding `Room` objects (id = 5-char
  human-typable code, e.g. `K7Q2F`). No database in v1; rooms die with the
  process. Scoreboard persists only for the lifetime of the room.
- **Bots run inside the server process** (ADR-004), acting through the same
  intent interface as humans — the room logic cannot tell them apart.
- **Reconnect:** clients get a `session_token` on first join; reconnecting with
  the token within the same round reclaims the seat from the stand-in bot.

## Consequences

- (+) Cheat-proof by construction; single rules engine (ADR-003) used by both
  sides; bots and disconnect-replacement are trivial because bots are
  first-class seat occupants on the server.
- (+) JSON protocol is debuggable with any WebSocket client and testable
  without Godot UI.
- (−) Requires hosting an always-on process (covered in ADR-005) — heavier than
  a static-only deployment.
- (−) JSON is more verbose than binary; acceptable at domino-game message rates
  (a few messages per second per room, tiny payloads).
- (−) No persistence: a server restart kills active games. Acceptable for v1;
  revisit with Redis/SQLite snapshotting if uptime becomes a requirement.
