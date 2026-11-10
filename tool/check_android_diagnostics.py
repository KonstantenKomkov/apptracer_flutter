#!/usr/bin/env python3
"""Run the optional release fixture on an explicit disposable emulator.

Clears only the .diagnostics example package. Restores radio/battery overrides;
never records raw heap/disk bodies or credentials. This is local HTTP acceptance,
not delivery to the vendor console or certification of consent cleanup.
"""
import argparse
import hashlib
import http.server
import json
import os
from pathlib import Path
import shutil
import subprocess
import threading
import time
import urllib.parse
import uuid

PACKAGE = 'ru.apptracer.flutter.apptracer_flutter_example.diagnostics'
ACTIVITY = 'ru.apptracer.flutter.apptracer_flutter_example.DiagnosticsActivity'
PORT = 37018


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--serial', required=True)
    parser.add_argument('--apk', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    adb = shutil.which('adb') or str(Path(os.environ.get('ANDROID_SDK_ROOT', Path.home() / 'Library/Android/sdk')) / 'platform-tools/adb')

    def call(*command, check=True):
        return subprocess.run([adb, '-s', args.serial, *command], capture_output=True,
                              text=True, check=check, timeout=90).stdout.strip()

    if call('shell', 'getprop', 'ro.kernel.qemu') != '1':
        raise SystemExit('This fixture requires a disposable emulator, not a physical device')
    args.output.mkdir(parents=True, exist_ok=True)
    wifi = call('shell', 'settings', 'get', 'global', 'wifi_on')
    mobile = call('shell', 'settings', 'get', 'global', 'mobile_data')
    requests = []
    tokens = {}
    lock = threading.Lock()

    class Sink(http.server.BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def do_POST(self):
            # The inspected SDK uses Content-Length. Reject other framing so a
            # partial body cannot be mistaken for successful delivery.
            if not self.headers.get('Content-Length'):
                self.send_error(411)
                return
            size = int(self.headers['Content-Length'])
            if size > 100 * 1024 * 1024:
                self.send_error(413)
                return
            body = self.rfile.read(size)
            parsed = urllib.parse.urlsplit(self.path)
            response = {'success': True}
            item = {'path': parsed.path, 'bytes': len(body), 'sha256': hashlib.sha256(body).hexdigest()}
            with lock:
                if parsed.path.endswith('/initUpload'):
                    data = json.loads(body)
                    token = str(uuid.uuid4())
                    tokens[token] = data['feature']
                    item['feature'] = data['feature']
                    response['uploadToken'] = token
                elif parsed.path.endswith('/upload'):
                    token = urllib.parse.parse_qs(parsed.query).get('uploadToken', [''])[0]
                    item['feature'] = tokens.get(token, 'unknown')
                requests.append(item)
            encoded = json.dumps(response).encode()
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(encoded)))
            self.end_headers()
            self.wfile.write(encoded)

    server = None
    try:
        call('install', '-r', str(args.apk.resolve()))
        call('shell', 'dumpsys', 'battery', 'unplug')
        for online in [False, True]:
            phase = 'online' if online else 'offline'
            call('shell', 'am', 'force-stop', PACKAGE)
            call('shell', 'pm', 'clear', PACKAGE)
            call('shell', 'svc', 'data', 'disable')
            call('shell', 'svc', 'wifi', 'enable' if online else 'disable')
            if online:
                server = http.server.ThreadingHTTPServer(('127.0.0.1', PORT), Sink)
                threading.Thread(target=server.serve_forever, daemon=True).start()
                call('reverse', 'tcp:' + str(PORT), 'tcp:' + str(PORT))
            else:
                call('reverse', '--remove', 'tcp:' + str(PORT), check=False)
            # Connectivity propagation happens independently of the adb command.
            time.sleep(8)
            call('shell', 'am', 'start', '-n', PACKAGE + '/' + ACTIVITY,
                 '--ez', 'online', str(online).lower())
            print('START', phase, flush=True)
            deadline = time.monotonic() + 240
            last_stage = None
            while time.monotonic() < deadline:
                raw = call('shell', 'cat', '/sdcard/Android/data/' + PACKAGE + '/files/diagnostics.json', check=False)
                try:
                    result = json.loads(raw)
                except ValueError:
                    time.sleep(1)
                    continue
                stage = result['stage']
                if stage != last_stage:
                    print(phase, stage, flush=True)
                    last_stage = stage
                (args.output / (phase + '.json')).write_text(json.dumps(result, indent=2) + '\n')
                if stage == 'error':
                    raise RuntimeError(result['details'])
                if stage == 'complete-' + phase:
                    break
                time.sleep(1)
            else:
                raise RuntimeError('Timed out waiting for ' + phase)
        with lock:
            evidence = list(requests)
        (args.output / 'http.json').write_text(json.dumps(evidence, indent=2) + '\n')
        uploads = [r for r in evidence if r['path'] == '/api/sample/upload']
        features = {name: sum(r['feature'] == name for r in uploads)
                    for name in ['HEAP_DUMP', 'DISK_USAGE']}
        if len(uploads) != 3 or features != {'HEAP_DUMP': 1, 'DISK_USAGE': 2} or any(r['bytes'] == 0 for r in uploads):
            raise RuntimeError('Expected two disk samples and one heap sample: ' + str(evidence))
        print('PASS: offline execution and online sample delivery; raw bodies discarded', flush=True)
    finally:
        call('shell', 'am', 'force-stop', PACKAGE, check=False)
        call('shell', 'svc', 'wifi', 'enable' if wifi == '1' else 'disable', check=False)
        call('shell', 'svc', 'data', 'enable' if mobile == '1' else 'disable', check=False)
        call('shell', 'dumpsys', 'battery', 'reset', check=False)
        call('reverse', '--remove', 'tcp:' + str(PORT), check=False)
        if server:
            server.shutdown()
            server.server_close()


if __name__ == '__main__':
    main()
