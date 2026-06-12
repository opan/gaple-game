#!/usr/bin/env python3
"""Serve a Godot Web export locally with the COOP/COEP headers the engine needs
for SharedArrayBuffer/threads (ADR-005, PHASE_2_PLAN.md §11).

Usage:
    python3 tools/serve_web.py [port] [directory]
Defaults: port 8060, directory build/web
Then open http://localhost:<port>/ in a browser.
"""
import http.server
import socketserver
import sys
from functools import partial

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8060
DIRECTORY = sys.argv[2] if len(sys.argv) > 2 else "build/web"


class CrossOriginIsolatedHandler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cache-Control", "no-store")
        super().end_headers()


def main() -> None:
    handler = partial(CrossOriginIsolatedHandler, directory=DIRECTORY)
    with socketserver.TCPServer(("", PORT), handler) as httpd:
        print(f"Serving {DIRECTORY!r} at http://localhost:{PORT}/ "
              f"(COOP/COEP enabled). Ctrl-C to stop.")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nstopped.")


if __name__ == "__main__":
    main()
