#!/usr/bin/env python3
"""Serve the fisicas web demo and open it in a browser.

Usage:
    python3 serve_web.py [port]
"""

import http.server
import socketserver
import sys
import webbrowser
from pathlib import Path

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
WEB_DIR = Path(__file__).resolve().parent.parent.parent / "zig-out" / "web"


def main() -> int:
    if not WEB_DIR.is_dir():
        print(f"error: {WEB_DIR} does not exist.")
        print("Run `zig build demo-web` first.")
        return 1

    handler = lambda *args, **kwargs: http.server.SimpleHTTPRequestHandler(
        *args, directory=str(WEB_DIR), **kwargs
    )

    url = f"http://localhost:{PORT}/ballistic_web.html"
    print(f"Serving {WEB_DIR} at {url}  (Ctrl+C to stop)")

    with socketserver.TCPServer(("localhost", PORT), handler) as httpd:
        webbrowser.open(url)
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nStopped.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
