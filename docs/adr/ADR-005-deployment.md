# ADR-005: Deployment — static web client + containerized game server

- **Status:** Accepted
- **Date:** 2026-06-12
- **Deciders:** opan.mustopah

## Context

ADR-001/002 produce two artifacts: a static Web export (HTML + wasm + pck) and
a headless Godot server process needing a public WSS endpoint. Constraints:
hobby-scale budget, the web host must allow setting COOP/COEP headers (Godot
threads), browsers require **wss://** (TLS) when the page is served over https.

## Decision

- **Client:** static hosting on **Cloudflare Pages** (free, custom headers via
  `_headers` file):
  ```
  /*
    Cross-Origin-Opener-Policy: same-origin
    Cross-Origin-Embedder-Policy: require-corp
  ```
  Fallback option: itch.io (sets these headers automatically) for playtest
  builds.
- **Server:** Docker image `FROM ubuntu` + official Godot headless binary,
  running `godot --headless -- --server --port=9000`, deployed on **Fly.io**
  (free/cheap tier, built-in TLS termination → wss, closest-region anycast).
  Health check: TCP on the WS port. One instance, vertical scaling only — a
  single small VM handles hundreds of concurrent domino rooms.
- **Config:** client reads the server URL from `client/net/config.gd`
  (`wss://gaple-server.fly.dev` in release, `ws://localhost:9000` in debug,
  switched on `OS.is_debug_build()` + an optional `?server=` URL query param
  for testing).
- **CI/CD (GitHub Actions):** on every push to `main`:
  1. Run GUT tests headless (fail fast).
  2. Export Web build (using `barichello/godot-ci` style container, version
     pinned to the project's Godot version).
  3. Deploy export to Cloudflare Pages; build + push server image to Fly.io.
  Version stamp: protocol version `v` (ADR-002) checked at connect; mismatched
  client gets an `update_required` error.

## Consequences

- (+) Zero-to-low cost; TLS handled by both platforms; one-command deploys.
- (+) Protocol version check prevents stale cached clients from corrupting
  rooms after a deploy.
- (−) Single server region adds latency for far players — irrelevant for a
  turn-based game.
- (−) Fly.io deploy restarts kill in-progress games (no persistence per
  ADR-002); deploys should be done at low-traffic times in v1.
