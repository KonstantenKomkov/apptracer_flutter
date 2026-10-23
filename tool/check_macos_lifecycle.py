#!/usr/bin/env python3
"""Exercise actual release-app consent/queue lifecycle against loopback only.

Each launch is a fresh process; stdin commands use the opt-in example driver.
HTTP 503 retains envelopes in the official SDK cache. No credentials are read.
"""
import argparse
import gzip
import json
import os
from pathlib import Path
import queue
import subprocess
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from check_macos_desktop import envelope_events


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    app = args.app.resolve()
    name = subprocess.check_output(['/usr/libexec/PlistBuddy', '-c', 'Print :CFBundleExecutable',
                                    str(app / 'Contents/Info.plist')], text=True).strip()
    executable = app / 'Contents/MacOS' / name
    received, steps, failures = [], [], []
    mode = 'online'
    release_response = threading.Event()
    run = str(uuid.uuid4())

    class Receiver(BaseHTTPRequestHandler):
        def log_message(self, *unused):
            pass

        def do_POST(self):
            try:
                data = self.rfile.read(int(self.headers['Content-Length']))
                if self.headers.get('Content-Encoding') == 'gzip':
                    data = gzip.decompress(data)
                events = [event for kind, event in envelope_events(data) if kind == 'event']
                current_mode = mode
                received.append({'time': time.monotonic(), 'mode': current_mode,
                                 'path': self.path, 'events': events})
                if current_mode == 'hold':
                    release_response.wait(20)
                self.send_response(503 if current_mode == 'offline' else 200)
                self.send_header('Content-Length', '2')
                self.end_headers()
                self.wfile.write(b'{}')
            except (BrokenPipeError, ConnectionResetError):
                pass  # Expected when stop cancels an in-flight request.
            except Exception as error:
                failures.append('receiver: ' + repr(error))

    server = ThreadingHTTPServer(('127.0.0.1', 0), Receiver)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    env = dict(os.environ, TRACER_MACOS_SENTRY_DSN=f'http://lifecycle@127.0.0.1:{server.server_port}/42',
               TRACER_SCENARIO='lifecycle', TRACER_RUN_ID=run)
    process = None
    replies = queue.Queue()
    outputs = []
    # This checked-in example is sandboxed and has a fixed bundle identifier.
    library = Path.home() / 'Library/Containers/dev.apptracer.apptracerDesktopExample/Data/Library'
    storage = library / 'Application Support/apptracer_desktop/dev.apptracer.apptracerDesktopExample/v1'

    def assert_cleared():
        assert {p.name for p in storage.iterdir()} == {'queue', 'revoked'}
        assert (storage / 'queue').is_file() and (storage / 'queue').stat().st_size == 0
        assert not (library / 'Caches/async.log').exists()

    def wait_until(predicate, description, timeout=15):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if predicate():
                return
            if process is not None and process.poll() is not None:
                raise AssertionError(f'{description}: app exited {process.returncode}; {outputs[-5:]}')
            time.sleep(0.05)
        raise AssertionError('timeout: ' + description)

    def launch():
        nonlocal process, replies
        replies = queue.Queue()
        process = subprocess.Popen([str(executable)], cwd=executable.parent, env=env,
                                   stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                   stderr=subprocess.STDOUT, text=True, bufsize=1)
        child, mailbox = process, replies

        def read():
            for line in child.stdout:
                outputs.append(line.strip())
                if 'APPTRACER_READY ' in line:
                    mailbox.put({'ready': True})
                elif 'APPTRACER_RESULT ' in line:
                    mailbox.put(json.loads(line.split('APPTRACER_RESULT ', 1)[1]))
        threading.Thread(target=read, daemon=True).start()
        wait_until(lambda: not mailbox.empty(), 'application ready')
        assert mailbox.get_nowait() == {'ready': True}
        command('state', expected='disabled')

    def terminate():
        if process and process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)

    def command(action, expected=None, **values):
        identifier = len(steps)
        process.stdin.write(json.dumps(dict(id=identifier, action=action, **values)) + '\n')
        process.stdin.flush()
        if action == 'crash':
            assert process.wait(timeout=10) != 0
            steps.append({'action': action, 'exit_code': process.returncode})
            return
        wait_until(lambda: not replies.empty(), action, timeout=20)
        result = replies.get_nowait()
        assert result.get('id') == identifier and 'error' not in result, result
        assert result['enabled'] == (result['state'] == 'enabled'), result
        if expected:
            assert result['state'] == expected, result
        steps.append(dict(action=action, **result))

    def events_since(index):
        return [event for request in received[index:] for event in request['events']]

    def wait_marker(marker, index):
        wait_until(lambda: marker in json.dumps(events_since(index)), 'event ' + marker)

    def quiet(index, seconds=2):
        time.sleep(seconds)
        assert len(received) == index, f'unexpected requests: {received[index:]}'
        assert process.poll() is None, outputs[-5:]

    try:
        # Disabled bootstrap, cleanup before SDK start, idempotent start/stop.
        launch()
        command('clear', expected='disabled')
        assert_cleared()
        quiet(0)
        command('start', expected='enabled')
        command('start', expected='enabled')
        command('identify', user='account-A')
        mode = 'offline'
        command('capture', message='clear-offline-account-A')
        wait_marker('clear-offline-account-A', 0)
        command('stop', expected='restartRequired')
        command('stop', expected='restartRequired')
        stopped_at = len(received)
        command('capture', message='forbidden-after-stop')
        command('start', expected='restartRequired', preserve=True)
        command('clear', expected='restartRequired')
        command('clear', expected='restartRequired')
        quiet(stopped_at)
        assert_cleared()
        command('crash')  # Crash after stop/clear must never be replayed.

        mode = 'online'
        launch()
        quiet(stopped_at)  # Even a queued native crash cannot bypass deferred start.
        command('start', expected='enabled', preserve=True)
        quiet(stopped_at)
        command('identify', user='account-B')
        command('capture', message='fresh-account-B')
        wait_marker('fresh-account-B', stopped_at)
        delivered = events_since(stopped_at)
        assert len(delivered) == 1 and 'account-A' not in json.dumps(delivered)
        assert delivered[0]['user']['id'] == 'account-B'
        command('clear', expected='restartRequired')
        terminate()

        # A normal offline restart may preserve authorized reports.
        mode = 'offline'
        launch()
        command('start', expected='enabled')
        marker_index = len(received)
        command('capture', message='authorized-offline-restart')
        wait_marker('authorized-offline-restart', marker_index)
        terminate()
        mode = 'online'
        marker_index = len(received)
        launch()
        quiet(marker_index)
        command('start', expected='enabled', preserve=True)
        wait_marker('authorized-offline-restart', marker_index)
        command('clear', expected='restartRequired')
        terminate()

        # Default preserve=false discards, even without a preceding stop.
        mode = 'offline'
        launch()
        command('start', expected='enabled')
        marker_index = len(received)
        command('capture', message='discard-default-offline')
        wait_marker('discard-default-offline', marker_index)
        terminate()
        mode = 'online'
        marker_index = len(received)
        launch()
        command('start', expected='enabled')
        quiet(marker_index)
        command('clear', expected='restartRequired')
        terminate()

        # Explicit stop before the SDK's first start also revokes older reports.
        mode = 'offline'
        launch()
        command('start', expected='enabled')
        marker_index = len(received)
        command('capture', message='revoked-before-first-start')
        wait_marker('revoked-before-first-start', marker_index)
        terminate()
        mode = 'online'
        marker_index = len(received)
        launch()
        command('stop', expected='disabled')
        terminate()
        launch()
        command('start', expected='enabled', preserve=True)
        quiet(marker_index)
        command('clear', expected='restartRequired')
        terminate()

        # Stop cancels a held request and revokes queue replay without clear.
        mode = 'hold'
        launch()
        command('start', expected='enabled')
        marker_index = len(received)
        command('capture', message='in-flight-before-stop')
        wait_marker('in-flight-before-stop', marker_index)
        command('capture', message='queued-behind-in-flight')
        command('stop', expected='restartRequired')
        stopped_at = len(received)
        release_response.set()
        command('capture', message='forbidden-after-cancel')
        quiet(stopped_at)
        command('crash')  # Stop alone must also disable the native crash writer.
        mode = 'online'
        launch()
        command('start', expected='enabled', preserve=True)
        quiet(stopped_at)
        command('clear', expected='restartRequired')
        assert_cleared()
        terminate()

        # A crash while authorized survives offline restart, but waits for start.
        launch()
        command('start', expected='enabled')
        command('identify', user='native-authorized-account')
        command('crash')
        marker_index = len(received)
        launch()
        quiet(marker_index)
        command('start', expected='enabled', preserve=True)
        wait_until(lambda: any(e.get('level') == 'fatal' for e in events_since(marker_index)), 'native crash replay')
        assert len(events_since(marker_index)) == 1
        command('clear', expected='restartRequired')
    except Exception as error:
        failures.append(repr(error))
    finally:
        release_response.set()
        terminate()
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)
    report = {'run_id': run, 'steps': steps, 'requests': received, 'failures': failures,
              'scope': 'local macOS release app; no Tracer console or server-symbolication claim'}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'steps': len(steps), 'requests': len(received), 'failures': failures,
                      'report': str(args.output)}, ensure_ascii=False))
    return bool(failures)


if __name__ == '__main__':
    raise SystemExit(main())
