# Gaple

A web-based multiplayer **Gaple** game — the traditional Indonesian double-six
domino game — for 2–4 players, mixing real players and computer bots freely.

Built with **Godot 4.6.3 (GDScript)**: one project produces both the browser
client and an authoritative headless server.

## Status

Early development. **Phases 0–1 are complete** — project bootstrap and the pure
rules engine (`core/`) with a full GUT test suite. Next up is Phase 2 (the local
single-player UI). See `PLAN.md` for the phased roadmap and `docs/GAME_RULES.md`
for the exact rules.

Run the rules-engine fuzz harness (random legal playouts):

```sh
godot --headless -s tools/fuzz_playout.gd -- --rounds=10000
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

# Headless game server (Ctrl-C to stop)
godot --headless -- --server --port=9000
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
