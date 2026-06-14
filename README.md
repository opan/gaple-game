# Gaple

A web-based multiplayer **Gaple** game — the traditional Indonesian double-six
domino game — for 2–4 players, mixing real players and computer bots freely.

Built with **Godot 4.6.3 (GDScript)**: one project produces both the browser
client and an authoritative headless server.

## Status

**Phases 0–4 are complete** — project bootstrap, the pure rules engine
(`core/`), the local single-player game (vs 1–3 bots with the full table UI),
the authoritative headless multiplayer server (`server/`), and the full
networked client (`client/net/`). Phase 5 (deployment to Fly.io + Cloudflare
Pages) is in progress. See `PLAN.md` for the roadmap and `docs/GAME_RULES.md`
for the exact rules.

## Requirements

- **Godot 4.6.3** (stable). Pinned — keep CI and the server Dockerfile in sync.
  - macOS: `brew install --cask godot`, then optionally symlink the CLI:
    `ln -sf /Applications/Godot.app/Contents/MacOS/Godot /opt/homebrew/bin/godot`
  - Verify: `godot --version` → `4.6.3.stable...`

## Running locally

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

### Web build (local)

```sh
# Requires the Godot 4.6.3 Web export templates (editor → Manage Export
# Templates, or download the matching .tpz).
mkdir -p build/web
godot --headless --export-release "Web" build/web/index.html

# Serve locally with the COOP/COEP headers the engine needs, then open the URL:
python3 tools/serve_web.py 8060 build/web   # http://localhost:8060/
```

## Tests

Unit tests use [GUT](https://github.com/bitwes/Gut) (vendored in
`addons/gut/`). Test directories are configured in `.gutconfig.json`.

```sh
# Run the whole suite (exit code 0 = all pass, 1 = any failure)
godot --headless -s addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json

# Run a single test script
godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_smoke.gd -gexit
```

Run the rules-engine fuzz harness (10 000 random legal playouts):

```sh
godot --headless -s tools/fuzz_playout.gd -- --rounds=10000
```

## Deployment

The live game runs on:

- **Client**: [Cloudflare Pages](https://pages.cloudflare.com/) — static Web export
- **Server**: [Fly.io](https://fly.io/) — headless Godot container

### First-time setup

1. **Fly.io**

   ```sh
   # Install flyctl, then:
   fly auth login
   fly apps create gaple-server          # must match app name in deploy/fly.toml
   fly deploy --config deploy/fly.toml
   ```

2. **Cloudflare Pages**

   Create a Pages project named `gaple-game` in the Cloudflare dashboard, then
   deploy the built `build/web/` directory (including the `_headers` file the CI
   copies from `deploy/pages_headers`).

3. **GitHub Secrets** (required for CI auto-deploy on merge to `main`):

   | Secret | Where to get it |
   |---|---|
   | `FLY_API_TOKEN` | `fly tokens create deploy` |
   | `CLOUDFLARE_API_TOKEN` | Cloudflare dashboard → API Tokens → create with "Cloudflare Pages: Edit" |
   | `CLOUDFLARE_ACCOUNT_ID` | Cloudflare dashboard → right sidebar |

### CI / CD

On every push to `main` the GitHub Actions pipeline (`ci.yml`) runs in order:

1. **tests** — full GUT suite (headless, exit-1 on any failure)
2. **export** — Web export → `build/web/` with `_headers` injected
3. **deploy** — client to Cloudflare Pages; server image to Fly.io

PRs run only the `tests` and `export` jobs; deploy is skipped.

## Documentation

| Document | Purpose |
|---|---|
| `PLAN.md` | Phased implementation plan, repo layout, network protocol |
| `docs/GAME_RULES.md` | Authoritative game rules (the engine's spec) |
| `docs/adr/` | Architecture Decision Records (engine, multiplayer, etc.) |
| `CLAUDE.md` | Orientation for AI coding agents working in this repo |

## License

TBD.
