# ADR-001: Game engine — Godot 4 with Web export

- **Status:** Accepted
- **Date:** 2026-06-12
- **Deciders:** opan.mustopah

## Context

We are building a web-based multiplayer Gaple (Indonesian dominoes) game for
2–4 players with mixed human/bot seats (see `docs/GAME_RULES.md`). The primary
delivery target is the browser. The project owner requested Godot, open to
alternatives.

Candidates considered:

1. **Godot 4.x (GDScript), HTML5/Web export** — full game engine, scene system,
   tweens/animation, one codebase can also run as a headless authoritative
   server (`--headless`), and later export native desktop/mobile builds for free.
2. **TypeScript + Phaser 3 or PixiJS + Node.js/Colyseus server** — web-native:
   smaller bundles (~1–2 MB vs Godot's ~35–50 MB wasm), no SharedArrayBuffer/
   COOP-COEP header requirements, better mobile-browser performance, huge npm
   ecosystem, server logic shares TypeScript types with the client.
3. **Plain DOM/CSS + WebSocket** — a domino game is simple enough for DOM, but
   animations, z-ordering, and a fanned-hand UI get painful; no reuse path.

Honest assessment: for a *pure web* 2D card game, option 2 is technically the
better web citizen (load time, mobile Safari behavior, hosting simplicity).
Option 1 wins on: requested by owner, single language/codebase for client +
server + bots, batteries-included tooling (scenes, tweens, UI containers,
particles), and future native exports.

## Decision

Use the **latest stable Godot 4.x with GDScript** for client, server, and
shared game logic, exporting the client to **Web (HTML5/wasm)**. The version is
pinned per-checkout; as of Phase 0 (2026-06-12) this is **Godot 4.6.3**.

Mitigations for Godot-on-web weaknesses:

- Serve the export behind correct **COOP/COEP headers** (required for threads);
  use the "Runnable in browser without threads" export option if targeting
  hosts that cannot set headers (itch.io sets them automatically).
- Keep assets procedural/minimal (domino tiles are vector-ish; draw them with
  `Polygon2D`/`draw_*` or one small atlas) to keep the wasm+pck download lean.
- Enforce the **strict core/client/server module split** (ADR-003) so that if
  web constraints ever force a rewrite to TypeScript, only rendering and
  transport are rewritten — the rules engine is a direct port.

## Consequences

- (+) One language (GDScript), one engine, one repo for client, server, bots.
- (+) Free path to desktop/mobile native builds later.
- (+) Headless Godot server reuses the exact rules engine the client uses —
  zero rules drift between client prediction and server authority.
- (−) ~35–50 MB initial web download; mitigate with a loading screen and asset
  discipline.
- (−) Web export needs COOP/COEP headers on the static host (documented in
  ADR-005).
- (−) GDScript has weaker static tooling than TypeScript; mitigate with
  `--check-only` CI script validation, typed GDScript (`var x: int`) required
  in `core/` and `server/`, and GUT unit tests (ADR-003).

## Revisit triggers

Reconsider option 2 (TypeScript + PixiJS) if: web bundle size becomes a real
user complaint, mobile-browser performance is unacceptable on mid-range phones,
or hosting constraints prevent setting COOP/COEP headers.
