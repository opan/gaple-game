# Gaple

A web-based multiplayer **Gaple** game — the traditional Indonesian double-six
domino game — for 2–4 players, mixing real players and computer bots freely.

Built with **Godot 4.6.3 (GDScript)**: one project produces both the browser
client and an authoritative headless server.

## Status

Early development. **Phases 0–3 are complete** — project bootstrap, the pure
rules engine (`core/`), the local single-player game (vs 1–3 bots with the full
table UI), and the authoritative headless multiplayer server (`server/`) with
rooms, bots, turn timers, disconnect/reconnect, and host migration. Next up is
Phase 4 (the networked client). See `PLAN.md` for the roadmap, the
`docs/PHASE_*_PLAN.md` files for per-phase detail, and `docs/GAME_RULES.md` for
the exact rules.

Run the rules-engine fuzz harness (random legal playouts):

```sh
godot --headless -s tools/fuzz_playout.gd -- --rounds=10000
```

### Web build

```sh
# Requires the Godot 4.6.3 Web export templates (editor → Manage Export
# Templates, or download the matching .tpz).
mkdir -p build/web
godot --headless --export-release "Web" build/web/index.html

# Serve locally with the COOP/COEP headers the engine needs, then open the URL:
python3 tools/serve_web.py 8060 build/web   # http://localhost:8060/
```

## Documentation

| Document | Purpose |
|---|---|
| `PLAN.md` | Phased implementation plan, repo layout, network protocol |
| `docs/GAME_RULES.md` | Authoritative game rules (the engine's spec) |
| `docs/adr/` | Architecture Decision Records (engine, multiplayer, etc.) |
| `CLAUDE.md` | Orientation for AI coding agents working in this repo |

## Requirements

- **Godot 4.6.3** (stable). Pinned — keep CI and the server Dockerfile in sync.
  - macOS: `brew install --cask godot`, then optionally symlink the CLI:
    `ln -sf /Applications/Godot.app/Contents/MacOS/Godot /opt/homebrew/bin/godot`
  - Verify: `godot --version` → `4.6.3.stable...`

## Running

```sh
# Client — open the project in the Godot editor and press F5.
godot --editor          # opens the editor; then F5 to run

# Headless multiplayer server (Ctrl-C to stop)
godot --headless -- --server --port=9000

# Demo: a script client plays a full round vs a server-side bot
godot --headless -s tools/ws_client.gd -- --url=ws://127.0.0.1:9000 --name=Demo
```

The `--server` flag goes after `--` so Godot passes it through as a user arg
(consumed by `main.gd`). Without it, the project boots the client.

## Tests

Unit tests use [GUT](https://github.com/bitwes/Gut) (vendored in
`addons/gut/`). Test directories are configured in `.gutconfig.json`.

```sh
# Run the whole suite (exit code 0 = all pass, 1 = any failure)
godot --headless -s addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json

# Run a single test script
godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_smoke.gd -gexit
```

## License

TBD.
