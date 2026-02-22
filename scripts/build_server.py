#!/usr/bin/env python3
"""
MacTunesRecs Build Server
Runs xcodebuild and serves build status as an HTML page on a port.
"""
import subprocess
import threading
import time
import html
from http.server import HTTPServer, BaseHTTPRequestHandler
from datetime import datetime

PORT = 8788
PROJECT_DIR = __file__.replace("/scripts/build_server.py", "")

state = {
    "output": "Building...",
    "status": "building",
    "last_run": None,
    "run_count": 0,
}

def run_build():
    state["status"] = "building"
    state["last_run"] = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    state["run_count"] += 1
    try:
        result = subprocess.run(
            [
                "xcodebuild", "build",
                "-project", "MacTunesRecs.xcodeproj",
                "-scheme", "MacTunesRecs",
                "-configuration", "Debug",
                "CODE_SIGN_IDENTITY=",
                "CODE_SIGNING_REQUIRED=NO",
                "CODE_SIGNING_ALLOWED=NO",
            ],
            cwd=PROJECT_DIR,
            capture_output=True,
            text=True,
            timeout=300,
        )
        combined = result.stdout + result.stderr
        state["output"] = combined
        state["status"] = "succeeded" if "BUILD SUCCEEDED" in combined else "failed"
    except Exception as e:
        state["output"] = str(e)
        state["status"] = "error"

def background_runner():
    while True:
        run_build()
        time.sleep(60)

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        status_color = {"succeeded": "#4ec94e", "failed": "#e05252", "building": "#e0c84e", "error": "#e05252"}.get(state["status"], "#fff")
        safe_output = html.escape(state["output"] or "")
        page = f"""<!DOCTYPE html>
<html>
<head>
  <title>MacTunesRecs Build</title>
  <meta http-equiv="refresh" content="30">
  <style>
    body {{ font-family: -apple-system, monospace; background: #1e1e1e; color: #d4d4d4; padding: 24px; margin: 0; }}
    h1 {{ color: #fff; }}
    .badge {{ display:inline-block; padding:4px 12px; border-radius:12px; background:{status_color}; color:#000; font-weight:bold; }}
    pre {{ background:#111; padding:16px; border-radius:8px; overflow:auto; font-size:12px; line-height:1.5; max-height:80vh; }}
    .meta {{ color:#888; font-size:13px; margin-bottom:16px; }}
  </style>
</head>
<body>
  <h1>🔨 MacTunesRecs — Build Status</h1>
  <p class="meta">Last run: {state['last_run']} &nbsp;|&nbsp; Run #{state['run_count']} &nbsp;|&nbsp; Auto-refreshes every 30s</p>
  <p><span class="badge">{state['status'].upper()}</span></p>
  <pre>{safe_output}</pre>
</body>
</html>"""
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.end_headers()
        self.wfile.write(page.encode())

    def log_message(self, format, *args):
        pass

if __name__ == "__main__":
    print(f"Starting MacTunesRecs Build Server on http://localhost:{PORT}")
    t = threading.Thread(target=background_runner, daemon=True)
    t.start()
    HTTPServer(("", PORT), Handler).serve_forever()
