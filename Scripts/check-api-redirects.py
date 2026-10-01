"""Loopback-only integration fixture. Uses a fake key; never reads user settings."""
import http.server
import os
import subprocess
import sys
import threading

counts = {"source": 0, "target": 0, "invalid_auth": 0}

class Target(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        counts["target"] += 1
        self.send_response(200)
        self.end_headers()
    do_POST = do_GET
    def log_message(self, *args):
        pass

target = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Target)

class Source(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        counts["source"] += 1
        if self.headers.get("Authorization") != "Bearer redirect-test-not-a-real-key":
            counts["invalid_auth"] += 1
        self.rfile.read(int(self.headers.get("Content-Length", "0")))
        self.send_response(int(self.path.split("/")[2]))
        self.send_header("Location", f"http://127.0.0.1:{target.server_port}/target")
        self.send_header("Content-Length", "0")
        self.end_headers()
    def log_message(self, *args):
        pass

source = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Source)
for server in (source, target):
    threading.Thread(target=server.serve_forever, daemon=True).start()
try:
    env = dict(os.environ, LINGGANGU_REDIRECT_TEST_URL=f"http://127.0.0.1:{source.server_port}")
    subprocess.run([sys.argv[1]], env=env, check=True, timeout=60)
    assert counts == {"source": 10, "target": 0, "invalid_auth": 0}, counts
    print("10 authenticated requests blocked at redirect; target received 0 requests.")
finally:
    for server in (source, target):
        server.shutdown()
        server.server_close()
