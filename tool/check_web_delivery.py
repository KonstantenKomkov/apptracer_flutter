#!/usr/bin/env python3
"""Loopback receiver for release web offline/reload/revoke acceptance."""
import argparse
import json
import threading
from urllib.parse import parse_qs, urlsplit
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
    stages = []

    class Handler(BaseHTTPRequestHandler):
        def cors(self):
            self.send_header('Access-Control-Allow-Origin', '*')
            self.send_header('Access-Control-Allow-Headers', 'content-type')

        def do_OPTIONS(self):
            self.send_response(204)
            self.cors()
            self.end_headers()

        def do_GET(self):
            url = urlsplit(self.path)
            stage = url.path.removeprefix('/verification/')
            reloaded = args.scenario in ('reload', 'stop')
            if (stage not in ('reloaded', 'complete') or
                parse_qs(url.query) != {'scenario': [args.scenario],
                                        'reloaded': [str(reloaded).lower()]}):
                self.send_error(400)
                return
            stages.append(stage)
            self.send_response(204)
            self.cors()
            self.end_headers()
            if stage == 'complete':
                finished.set()

        def do_POST(self):
            if self.path.split('?')[0] != '/api/crash/uploadBatch':
                self.send_response(404)
                self.end_headers()
                return
            body = self.rfile.read(int(self.headers.get('Content-Length', '0')))
            stages.append('upload')
            uploads.append(body)
            accepted = len(uploads) > 1
            self.send_response(200 if accepted else 503)
            self.cors()
            self.send_header('Content-Type', 'application/json')
            if not accepted:
                self.send_header('Retry-After', '2')
                self.send_header('Access-Control-Expose-Headers', 'Retry-After')
            self.end_headers()
            self.wfile.write(json.dumps({'success': accepted}).encode())

        def log_message(self, *_):
            pass

    server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    print(f'PORT={server.server_port}', flush=True)
    if args.open_url:
        separator = '&' if '?' in args.open_url else '?'
        subprocess.Popen(['open', '-a', 'Google Chrome',
                          f'{args.open_url}{separator}port={server.server_port}'])
    if not finished.wait(45):
        raise RuntimeError(f'page did not complete: {stages}')
    expected_stages = {
        'recovery': ['upload', 'upload', 'complete'],
        'reload': ['upload', 'reloaded', 'upload', 'complete'],
        'stop': ['upload', 'reloaded', 'complete'],
    }
    if stages != expected_stages[args.scenario] or len(uploads) != expected or len(set(uploads)) != 1:
        raise RuntimeError(f'unexpected delivery or navigation: {stages}')
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
