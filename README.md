# Gaple

A web-based multiplayer **Gaple** game — the traditional Indonesian double-six
domino game — for 2–4 players, mixing real players and computer bots freely.

Built with **Godot 4.6.3 (GDScript)**: one project produces both the browser
client and an authoritative headless server.

## Status

**Phases 0–4 are complete** — project bootstrap, the pure rules engine
(`core/`), the local single-player game (vs 1–3 bots with the full table UI),
the authoritative headless multiplayer server (`server/`), and the full
networked client (`client/net/`). Phase 5 (deployment) and Phase 6 (polish)
are in progress. See `PLAN.md` for the roadmap and `docs/GAME_RULES.md` for
the exact rules.

## Requirements

- **Godot 4.6.3** (stable). Pinned — keep CI and the server Dockerfile in sync.
  - macOS: `brew install --cask godot`, then optionally symlink the CLI:
    `ln -sf /Applications/Godot.app/Contents/MacOS/Godot /opt/homebrew/bin/godot`
  - Windows + WSL2 (Ubuntu): download the **Linux** build, not the Windows one,
    so the headless CLI runs natively inside WSL. Use the standard build (not
    `_mono`) since this project is plain GDScript:
    ```sh
    sudo apt-get update && sudo apt-get install -y unzip
    cd /tmp
    curl -L -o godot.zip \
      https://github.com/godotengine/godot/releases/download/4.6.3-stable/Godot_v4.6.3-stable_linux.x86_64.zip
    unzip godot.zip
    sudo install -m 755 Godot_v4.6.3-stable_linux.x86_64 /usr/local/bin/godot
    ```
    - The export templates are needed for `make web` / `make serve`. Install
      them once — only the two web files are required (~30 MB vs ~1 GB for all
      platforms):
      ```sh
      cd /tmp
      curl -L -o export_templates.tpz \
        https://github.com/godotengine/godot/releases/download/4.6.3-stable/Godot_v4.6.3-stable_export_templates.tpz
      mkdir -p ~/.local/share/godot/export_templates/4.6.3.stable
      cd ~/.local/share/godot/export_templates/4.6.3.stable
      unzip /tmp/export_templates.tpz templates/web_debug.zip templates/web_release.zip
      mv templates/web_debug.zip web_debug.zip
      mv templates/web_release.zip web_release.zip
      rmdir templates
      ```
    - The headless server and the full test suite run inside WSL with no extra
      setup — they need no display. To open the **editor** GUI (`make client`),
      you need WSLg — included in Windows 11 and recent Windows 10. Confirm it's
      active with `echo $DISPLAY` (should print `:0`) or `ls /mnt/wslg`; if so,
      `godot --editor` works. Otherwise run the editor from a native Windows
      Godot install instead.
  - Verify: `godot --version` → `4.6.3.stable...`
- **Python 3** (for the local web server)
- **Docker** (optional, for running the server as a container)

If `godot` is not on your `PATH`, pass it explicitly: `make test GODOT=/path/to/godot`.

## Quick start

```sh
make server        # start headless multiplayer server on :9000
make client        # open the Godot editor (press F5 to run the client)
make serve         # export web build and serve it at http://localhost:8060/
```

## All Makefile targets

| Target | Description |
|---|---|
| `make test` | Run the full GUT test suite (headless, exit 1 on failure) |
| `make test-one FILE=tests/unit/test_rules.gd` | Run a single test script |
| `make fuzz` | Random-playout fuzz harness (500 rounds by default) |
| `make server` | Headless multiplayer server on port 9000 |
| `make client` | Open the Godot editor |
| `make web` | Export the Web build to `build/web/` |
| `make serve` | Export + serve `build/web/` at http://localhost:8060/ with COOP/COEP |
| `make docker-build` | Build the server Docker image |
| `make docker-run` | Run the server Docker image on port 9000 |
| `make clean` | Remove `build/web/` |

Overridable variables:

```sh
make server PORT=9001
make serve WEB_PORT=8080
make fuzz FUZZ_ROUNDS=10000
make docker-run PORT=9001
```

## Deployment

The server runs as a Docker container (`deploy/Dockerfile`) behind a Cloudflare
Tunnel on a homelab k8s cluster (k3s). The static web client can be hosted on
Cloudflare Pages or any static host.

### Server (k8s)

```sh
# Apply manifests (fill in your Docker Hub username and domain first)
kubectl apply -k deployments/
```

See `deployments/` for the Deployment, Service, and Ingress manifests and
`deploy/docker-compose.yml` for a simpler single-host alternative.

### GitHub Secrets (required for CI image push)

| Secret | Description |
|---|---|
| `DOCKER_USERNAME` | Docker Hub username |
| `DOCKER_PASSWORD` | Docker Hub password or access token |

On every push to `main`, CI runs tests then builds and pushes
`$DOCKER_USERNAME/gaple-server:latest` to Docker Hub.

### Client (Cloudflare Pages)

Deploy `build/web/` (produced by `make web`) to any static host. The
`deploy/pages_headers` file must be served as `_headers` at the root so
browsers allow `SharedArrayBuffer` (required for Godot threads).

## Documentation

| Document | Purpose |
|---|---|
| `PLAN.md` | Phased implementation plan, repo layout, network protocol |
| `docs/GAME_RULES.md` | Authoritative game rules (the engine's spec) |
| `docs/adr/` | Architecture Decision Records (engine, multiplayer, etc.) |
| `CLAUDE.md` | Orientation for AI coding agents working in this repo |

## License

TBD.
