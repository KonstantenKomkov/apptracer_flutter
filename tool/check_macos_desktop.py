#!/usr/bin/env python3
"""Run the macOS/Windows/Linux release example against a loopback receiver.

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
import sys
import tempfile
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def read_http_body(stream, headers):
    """Accept both Cocoa's fixed-size and Dart HttpClient's chunked uploads."""
    limit = 32 * 1024 * 1024
    encoding = headers.get('Transfer-Encoding', '').lower()
    if encoding:
        if encoding != 'chunked':
            raise ValueError('unsupported transfer encoding')
        chunks = []
        total = 0
        while True:
            line = stream.readline(8193)
            if len(line) > 8192 or not line.endswith(b'\r\n'):
                raise ValueError('invalid chunk header')
            size = int(line.split(b';', 1)[0].strip(), 16)
            if size < 0 or total + size > limit:
                raise ValueError('invalid chunk size')
            if size == 0:
                for _ in range(100):
                    trailer = stream.readline(8193)
                    if trailer == b'\r\n':
                        return b''.join(chunks)
                    if len(trailer) > 8192 or not trailer.endswith(b'\r\n'):
                        raise ValueError('invalid chunk trailer')
                raise ValueError('too many chunk trailers')
            block = stream.read(size)
            if len(block) != size or stream.read(2) != b'\r\n':
                raise ValueError('truncated HTTP chunk')
            chunks.append(block)
            total += size
    length = int(headers['Content-Length'])
    if length < 0 or length > limit:
        raise ValueError('invalid content length')
    body = stream.read(length)
    if len(body) != length:
        raise ValueError('truncated HTTP body')
    return body


def envelope_items(data):
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
        yield item, payload


def envelope_events(data):
    for item, payload in envelope_items(data):
        yield item['type'], json.loads(payload) if item['type'] == 'event' else None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', required=True, type=Path)
    parser.add_argument('--scenario', choices=['smoke', 'disabled', 'deferred', 'native-crash'], default='smoke')
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    app = args.app.resolve()
    windows = os.name == 'nt'
    linux = sys.platform == 'linux'
    if (windows or linux) and args.scenario == 'native-crash':
        parser.error('Minidump delivery requires the separate native acceptance protocol')
    if windows:
        executable_name = 'apptracer_desktop_example.exe'
        for name in [executable_name, 'sentry.dll', 'flutter_windows.dll',
                     'crashpad_handler.exe', 'crashpad_wer.dll', 'data/app.so']:
            if not (app / name).is_file():
                parser.error('incomplete Windows bundle: ' + name)
    elif linux:
        executable_name = 'apptracer_desktop_example'
        for name in [executable_name, 'lib/libsentry.so', 'lib/sentry-crash',
                     'lib/libflutter_linux_gtk.so', 'lib/libapp.so', 'data/icudtl.dat']:
            if not (app / name).is_file():
                parser.error('incomplete Linux bundle: ' + name)
    else:
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
    outputs = []

    class Receiver(BaseHTTPRequestHandler):
        def log_message(self, *unused):
            pass

        def do_POST(self):
            try:
                payload = read_http_body(self.rfile, self.headers)
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
    dsn_key = ('TRACER_WINDOWS_SENTRY_DSN' if windows else
               'TRACER_LINUX_SENTRY_DSN' if linux else 'TRACER_MACOS_SENTRY_DSN')
    env[dsn_key] = f'http://local-probe@127.0.0.1:{server.server_port}/42'
    env['TRACER_RUN_ID'] = run_id
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
                outputs.append(line.strip())
                if len(outputs) > 30:
                    del outputs[0]
                if 'APPTRACER_READY ' in line:
                    messages.put(line.strip())
        threading.Thread(target=read_output, daemon=True).start()
        return child

    try:
        with tempfile.TemporaryDirectory(prefix='apptracer-desktop-') as directory:
            relocated = Path(directory) / ('Desktop probe Кириллица' + ('' if windows or linux else '.app'))
            shutil.copytree(app, relocated, symlinks=True)
            executable = (relocated if windows or linux else relocated / 'Contents/MacOS') / executable_name
            if linux:
                env['XDG_DATA_HOME'] = str(Path(directory) / 'Data Кириллица')
            ready_file = Path(directory) / 'ready.txt'
            if windows or linux:
                env['TRACER_PROBE_READY_FILE'] = str(ready_file)
            process = launch(executable, args.scenario)
            try:
                while time.monotonic() < deadline:
                    if (windows or linux) and not ready and ready_file.is_file():
                        # Readiness is written after bootstrap; tolerate a partial write.
                        status = ready_file.read_text(encoding='utf-8')
                        if ' state=' in status:
                            messages.put(status)
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
                    if windows:
                        # Target only this probe's process tree, including Crashpad.
                        subprocess.run(['taskkill', '/PID', str(process.pid), '/T', '/F'],
                                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                       check=False)
                    else:
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
            for exception in event.get('exception', {}).get('values', []):
                if 'desktop FlutterError probe' in exception.get('value', '') and exception.get('type') != 'FlutterError':
                    failures.append('FlutterError type was obfuscated')
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
              'logs': outputs if failures else [],
              'scope': 'local release app + official SDK, not Tracer console acceptance'}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'scenario': args.scenario, 'events': len(received),
                      'failures': failures, 'report': str(args.output)}, ensure_ascii=False))
    return 1 if failures else 0


if __name__ == '__main__':
    raise SystemExit(main())
