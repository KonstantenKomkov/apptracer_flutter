#!/usr/bin/env python3
"""Loopback receiver for release web offline/reload/revoke acceptance."""
import argparse
import json
import threading
import time
import subprocess
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--scenario', choices=['recovery', 'reload', 'stop'], required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--open-url', help='Release page URL; the receiver port is appended')
    args = parser.parse_args()
    uploads = []
    expected = 1 if args.scenario == 'stop' else 2
    finished = threading.Event()

    class Handler(BaseHTTPRequestHandler):
        def cors(self):
            self.send_header('Access-Control-Allow-Origin', '*')
            self.send_header('Access-Control-Allow-Headers', 'content-type')

        def do_OPTIONS(self):
            self.send_response(204)
            self.cors()
            self.end_headers()

        def do_POST(self):
            if self.path.split('?')[0] != '/api/crash/uploadBatch':
                self.send_response(404)
                self.end_headers()
                return
            body = self.rfile.read(int(self.headers.get('Content-Length', '0')))
            uploads.append(body)
            accepted = len(uploads) > 1
            self.send_response(200 if accepted else 503)
            self.cors()
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({'success': accepted}).encode())
            if len(uploads) == expected and args.scenario != 'stop':
                assert uploads[0] == uploads[1], 'retried payload changed'
                finished.set()

        def log_message(self, *_):
            pass

    server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    print(f'PORT={server.server_port}', flush=True)
    if args.open_url:
        separator = '&' if '?' in args.open_url else '?'
        subprocess.Popen(['open', '-a', 'Google Chrome',
                          f'{args.open_url}{separator}port={server.server_port}'])
    if args.scenario == 'stop':
        finished.wait(8)
        assert len(uploads) == expected, f'revoked event retried: {len(uploads)}'
    else:
        assert finished.wait(30), f'expected {expected} uploads, got {len(uploads)}'
    time.sleep(0.2)
    args.output.write_text(json.dumps({
        'scenario': args.scenario,
        'uploads': len(uploads),
        'samePayload': len(set(uploads)) == 1,
        'revokeHeld': args.scenario != 'stop' or len(uploads) == 1,
    }, indent=2))
    server.shutdown()
    server.server_close()
    print(f'RESULT={args.output}', flush=True)


if __name__ == '__main__':
    main()
