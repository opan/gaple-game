GODOT      ?= godot
PORT       ?= 9000
WEB_PORT   ?= 8060
WEB_DIR    := build/web
FUZZ_ROUNDS ?= 500

.PHONY: help test test-one fuzz server client web serve docker-build docker-run clean

help:
	@echo "Usage: make <target>"
	@echo ""
	@echo "  test               Run the full GUT test suite (headless)"
	@echo "  test-one FILE=...  Run a single test script, e.g. FILE=tests/unit/test_rules.gd"
	@echo "  fuzz               Run the random-playout fuzz harness (FUZZ_ROUNDS=$(FUZZ_ROUNDS))"
	@echo "  server             Start the headless multiplayer server on PORT=$(PORT)"
	@echo "  client             Open the Godot editor (press F5 to run)"
	@echo "  web                Export the Web build to $(WEB_DIR)/"
	@echo "  serve              Serve $(WEB_DIR)/ locally on WEB_PORT=$(WEB_PORT) with COOP/COEP"
	@echo "  docker-build       Build the server Docker image"
	@echo "  docker-run         Run the server Docker image on PORT=$(PORT)"
	@echo "  clean              Remove the web build output"
	@echo ""
	@echo "Override defaults: make server PORT=9001   make serve WEB_PORT=8080"

test:
	$(GODOT) --headless -s addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json

test-one:
	$(GODOT) --headless -s addons/gut/gut_cmdln.gd -gtest=res://$(FILE) -gexit

fuzz:
	$(GODOT) --headless -s tools/fuzz_playout.gd -- --rounds=$(FUZZ_ROUNDS)

server:
	$(GODOT) --headless -- --server --port=$(PORT)

client:
	$(GODOT) --editor

web:
	mkdir -p $(WEB_DIR)
	$(GODOT) --headless --export-release "Web" $(WEB_DIR)/index.html

serve: web
	python3 tools/serve_web.py $(WEB_PORT) $(WEB_DIR)

docker-build:
	docker build -f deploy/Dockerfile -t gaple-server .

docker-run:
	docker run --rm -p $(PORT):$(PORT) gaple-server

clean:
	rm -rf $(WEB_DIR)
