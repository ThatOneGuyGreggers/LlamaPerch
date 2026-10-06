#!/usr/bin/python3
"""Local test process. Never loads a model or connects outside loopback."""
import argparse
import json
import os
import signal
import sys
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

FLAGS = '--model --host --port --ctx-size --threads --threads-batch --parallel --n-gpu-layers --device --no-op-offload'
if '--version' in sys.argv:
    print('fixture version 0.0.1')
    sys.exit(0)
if '--help' in sys.argv:
    print(FLAGS)
    sys.exit(0)
parser = argparse.ArgumentParser()
parser.add_argument('--model', required=True)
parser.add_argument('--port', type=int, required=True)
args, _ = parser.parse_known_args()
mode = os.path.basename(args.model)
if 'early-exit' in mode:
    print('fixture: rejected model', file=sys.stderr, flush=True)
    sys.exit(7)
if 'no-listener' in mode:
    while True:
        time.sleep(0.1)  # The lifecycle test terminates this process after verifying false readiness.
if 'ignore-term' in mode:
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
if 'flood' in mode:
    for _ in range(300):
        sys.stdout.write('x' * 4096)
        sys.stderr.write('y' * 4096)
    sys.stdout.flush()
    sys.stderr.flush()
started = time.monotonic()

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        loading = 'loading' in mode or ('delay' in mode and time.monotonic() - started < 2)
        payload = {'status': 'ok'} if not loading else {'error': 'Loading model'}
        body = json.dumps(payload).encode()
        if 'oversized' in mode:
            body = b'x' * 20000
        self.send_response(503 if loading else 200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass  # Clients intentionally cancel oversized and timed-out requests.

    def log_message(self, *_):
        pass  # Keep fixture output deterministic; flood mode supplies explicit output.

HTTPServer.allow_reuse_address = True
server = HTTPServer(('127.0.0.1', args.port), Handler)
print('fixture: listening', flush=True)
try:
    server.serve_forever(poll_interval=0.05)
finally:
    server.server_close()
