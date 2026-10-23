#!/usr/bin/env python3
"""Run the release example outside the checkout against a loopback receiver.

This proves local SDK delivery only, not Tracer ingestion or symbolication.
No real credentials are read. Only this script's example process is terminated.
"""
import argparse
import gzip
import json
import os
from pathlib import Path
import queue
import shutil
import subprocess
import tempfile
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def envelope_events(data):
    """Read length-delimited Sentry items; attachments can contain newlines."""
    _, _, data = data.partition(b'\n')
    while data.strip():
        header, separator, data = data.partition(b'\n')
        if not separator:
            raise ValueError('missing item header delimiter')
        item = json.loads(header)
        if 'length' in item:
            length = int(item['length'])
            if length < 0 or length > len(data):
                raise ValueError('invalid item length')
            payload, data = data[:length], data[length:]
            data = data.removeprefix(b'\n')
        else:
            payload, _, data = data.partition(b'\n')
        yield item['type'], json.loads(payload) if item['type'] == 'event' else None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', required=True, type=Path)
    parser.add_argument('--scenario', choices=['smoke', 'disabled', 'deferred', 'native-crash'], default='smoke')
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    app = args.app.resolve()
    executable_name = subprocess.check_output(
        ['/usr/libexec/PlistBuddy', '-c', 'Print :CFBundleExecutable', str(app / 'Contents/Info.plist')],
        text=True).strip()
    incoming = queue.Queue()
    messages = queue.Queue()
    run_id = str(uuid.uuid4())
    received = []
    kinds = []
    requests = []
    failures = []

    class Receiver(BaseHTTPRequestHandler):
        def log_message(self, *unused):
            pass

        def do_POST(self):
            try:
                payload = self.rfile.read(int(self.headers['Content-Length']))
                if self.headers.get('Content-Encoding') == 'gzip':
                    payload = gzip.decompress(payload)
                items = list(envelope_events(payload))
                incoming.put((self.path, items, None))
                self.send_response(200)
                self.send_header('Content-Length', '2')
                self.end_headers()
                self.wfile.write(b'{}')
            except Exception as error:
                incoming.put((self.path, [], type(error).__name__))
                self.send_error(400)

    server = ThreadingHTTPServer(('127.0.0.1', 0), Receiver)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    env = os.environ.copy()
    env.update(TRACER_MACOS_SENTRY_DSN=f'http://local-probe@127.0.0.1:{server.server_port}/42',
               TRACER_RUN_ID=run_id)
    process = None
    ready = False
    native_crashed = False
    deadline = time.monotonic() + 45
    settled_at = None

    def launch(executable, scenario):
        child_env = dict(env, TRACER_SCENARIO=scenario)
        child = subprocess.Popen([str(executable)], cwd=executable.parent,
                                 env=child_env, stdout=subprocess.PIPE,
                                 stderr=subprocess.STDOUT, text=True)

        def read_output():
            for line in child.stdout:
                if 'APPTRACER_READY ' in line:
                    messages.put(line.strip())
        threading.Thread(target=read_output, daemon=True).start()
        return child

    try:
        with tempfile.TemporaryDirectory(prefix='apptracer-macos-') as directory:
            relocated = Path(directory) / 'Desktop probe Кириллица.app'
            shutil.copytree(app, relocated, symlinks=True)
            executable = relocated / 'Contents/MacOS' / executable_name
            process = launch(executable, args.scenario)
            try:
                while time.monotonic() < deadline:
                    while not messages.empty():
                        message = messages.get_nowait()
                        expected_enabled = args.scenario not in ('disabled', 'deferred')
                        if f'enabled={str(expected_enabled).lower()}' not in message or 'backend=sentry-sdk' not in message:
                            failures.append('unexpected application collection state')
                        ready = True
                        if args.scenario in ('disabled', 'deferred'):
                            settled_at = time.monotonic() + 3
                    try:
                        path, items, error = incoming.get(timeout=0.1)
                        requests.append(path)
                        if path != '/api/42/envelope/':
                            failures.append('unexpected ingest path')
                        if error:
                            failures.append('invalid SDK envelope: ' + error)
                        for kind, event in items:
                            kinds.append(kind)
                            if kind == 'event':
                                received.append(event)
                        expected_count = 3 if args.scenario == 'smoke' else 1
                        if len(received) >= expected_count:
                            settled_at = time.monotonic() + 2
                    except queue.Empty:
                        pass
                    exit_code = process.poll()
                    if exit_code is not None:
                        if args.scenario == 'native-crash' and not native_crashed and exit_code != 0 and ready:
                            native_crashed = True
                            process = launch(executable, 'idle')
                        else:
                            failures.append(f'unexpected application exit: {exit_code}')
                            break
                    if settled_at and time.monotonic() >= settled_at:
                        break
                else:
                    failures.append('timed out waiting for application/SDK')
            finally:
                if process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait(timeout=5)
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)

    if not ready:
        failures.append('application did not report ready')
    if args.scenario in ('disabled', 'deferred'):
        if requests:
            failures.append('traffic before collection authorization')
    elif args.scenario == 'smoke':
        if len(received) != 3:
            failures.append(f'expected exactly 3 events, got {len(received)}')
        values = [str(event.get('exception', {})) for event in received]
        for marker in ['desktop handled probe', 'desktop FlutterError probe', 'desktop async probe']:
            if sum(marker in value for value in values) != 1:
                failures.append('missing or duplicated error: ' + marker)
        for event in received:
            if event.get('tags', {}).get('probe_run') != run_id:
                failures.append('wrong run/project scope')
            if event.get('user', {}).get('id') != 'desktop-test-user':
                failures.append('missing user')
            if not event.get('breadcrumbs'):
                failures.append('missing breadcrumb')
        if any(kind != 'event' for kind in kinds):
            failures.append('unexpected automatic envelope items')
    else:
        if not native_crashed or len(received) != 1:
            failures.append('native crash/relaunch delivery not confirmed')
        else:
            if received[0].get('level') != 'fatal':
                failures.append('native event is not fatal')
            if received[0].get('tags', {}).get('probe_run') != run_id:
                failures.append('native event belongs to a previous run')

    report = {'scenario': args.scenario, 'run_id': run_id, 'ready': ready,
              'native_crashed': native_crashed, 'requests': requests,
              'item_types': kinds, 'events': received, 'failures': failures,
              'scope': 'local release app + official SDK, not Tracer console acceptance'}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'scenario': args.scenario, 'events': len(received),
                      'failures': failures, 'report': str(args.output)}, ensure_ascii=False))
    return 1 if failures else 0


if __name__ == '__main__':
    raise SystemExit(main())
