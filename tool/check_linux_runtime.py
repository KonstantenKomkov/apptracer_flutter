#!/usr/bin/env python3
"""Ubuntu release lifecycle/native probes; loopback only, never Tracer credentials."""
import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path
import queue
import shutil
import signal
import socket
import struct
import subprocess
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from check_macos_desktop import envelope_items, read_http_body
from check_windows_native import multipart_dumps, span, u32
from elf_build_id import build_id


def inspect_linux_dump(data, executable):
    if data[:4] != b'MDMP':
        raise ValueError('not a minidump')
    count, directory = u32(data, 8), u32(data, 12)
    if count > 1000:
        raise ValueError('invalid stream count')
    exception, module = None, None
    for index in range(count):
        kind, size, offset = struct.unpack('<III', span(data, directory + index * 12, 12))
        stream = span(data, offset, size)
        if kind == 6:
            exception = u32(stream, 8)
        elif kind == 4:
            modules = u32(stream, 0)
            if modules > 10000:
                raise ValueError('invalid module count')
            for item in range(modules):
                record = span(stream, 4 + item * 108, 108)
                name_offset = u32(record, 20)
                name = span(data, name_offset + 4, u32(data, name_offset)).decode('utf-16-le')
                if Path(name).name == executable.name:
                    cv = span(data, u32(record, 80), u32(record, 76))
                    if cv[:4] != b'LEpB':
                        raise ValueError('missing ELF CodeView identity')
                    module = {'path': name, 'build_id': cv[4:].hex()}
    if exception != signal.SIGSEGV or module is None:
        raise ValueError('missing runner or expected SIGSEGV')
    if module['build_id'] != build_id(str(executable)):
        raise ValueError('minidump does not match runner ELF build-id')
    return {'sha256': hashlib.sha256(data).hexdigest(), 'bytes': len(data),
            'exception': exception, 'runner': module}


class Probe:
    def __init__(self, bundle, directory, dump_directory=None, windows=False):
        self.windows = windows
        name = 'apptracer_desktop_example' + ('.exe' if windows else '')
        self.executable = bundle / name
        self.storage = directory / 'Data Кириллица/apptracer_desktop' / name / 'v1'
        self.requests, self.steps, self.logs = [], [], []
        self.mode = 'online'
        self.expect_native_symbols = True
        self.process = None
        self.replies = queue.Queue()
        self.release_response = threading.Event()
        probe = self

        class Receiver(BaseHTTPRequestHandler):
            def log_message(self, *unused):
                pass

            def do_POST(self):
                try:
                    body = read_http_body(self.rfile, self.headers)
                    if self.headers.get('Content-Encoding') == 'gzip':
                        body = gzip.decompress(body)
                    request = {'path': self.path, 'mode': probe.mode}
                    dump = None
                    if self.path.split('?')[0] == '/api/42/minidump/':
                        dump = multipart_dumps(self.headers.get('Content-Type', ''), body)
                    elif self.path == '/api/42/envelope/':
                        request['events'] = []
                        for item, payload in envelope_items(body):
                            if item['type'] == 'event':
                                request['events'].append(json.loads(payload))
                            elif item.get('attachment_type') == 'event.minidump':
                                if dump is not None:
                                    raise ValueError('duplicate minidump')
                                dump = payload
                    else:
                        raise ValueError('unexpected ingest route')
                    if dump is not None:
                        if windows:
                            from check_windows_native import inspect_dump, pe_identity
                            request['dump'] = inspect_dump(dump, probe.executable.name)
                            assert request['dump']['runner']['codeview'] == pe_identity(probe.executable.read_bytes())
                            assert request['dump']['exception_code'] == '0xc0000005'
                        else:
                            request['dump'] = inspect_linux_dump(dump, probe.executable)
                        if str(bundle) not in request['dump']['runner']['path']:
                            raise ValueError('dump is from another probe process')
                        if dump_directory is not None:
                            dump_directory.mkdir(parents=True, exist_ok=True)
                            (dump_directory / (request['dump']['sha256'] + '.dmp')).write_bytes(dump)
                    probe.requests.append(request)
                    if request['mode'] == 'disconnected':
                        # A network failure has no HTTP response. The official
                        # The native envelope transport discards HTTP 5xx.
                        self.connection.shutdown(socket.SHUT_RDWR)
                        self.close_connection = True
                        return
                    if request['mode'] == 'hold':
                        self.connection.settimeout(.1)
                        deadline = time.monotonic() + 15
                        while not probe.release_response.is_set() and time.monotonic() < deadline:
                            try:
                                if not self.connection.recv(1, socket.MSG_PEEK):
                                    request['disconnected_before_response'] = True
                                    return
                            except ConnectionResetError:
                                request['disconnected_before_response'] = True
                                return
                            except socket.timeout:
                                pass
                    self.send_response(503 if request['mode'] == 'offline' else 200)
                    self.send_header('Content-Length', '2')
                    self.end_headers()
                    self.wfile.write(b'{}')
                except (BrokenPipeError, ConnectionResetError):
                    pass
                except Exception as error:
                    probe.requests.append({'error': str(error)})
                    self.send_error(400)

        self.server = ThreadingHTTPServer(('127.0.0.1', 0), Receiver)
        self.server.daemon_threads = True
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.env = dict(os.environ,
                        TRACER_LINUX_SENTRY_DSN=f'http://linux-probe@127.0.0.1:{self.server.server_port}/42',
                        TRACER_SCENARIO='lifecycle', TRACER_RUN_ID=directory.name,
                        XDG_DATA_HOME=str(directory / 'Data Кириллица'))
        if windows:
            self.env['TRACER_WINDOWS_SENTRY_DSN'] = self.env.pop('TRACER_LINUX_SENTRY_DSN')
            self.env['LOCALAPPDATA'] = self.env.pop('XDG_DATA_HOME')

    def wait(self, predicate, label, timeout=30):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if predicate():
                return
            time.sleep(.05)
        raise AssertionError(f'timeout: {label}; {self.logs[-5:]}')

    def launch(self):
        self.replies = queue.Queue()
        self.process = subprocess.Popen([str(self.executable)], cwd=self.executable.parent,
                                        env=self.env, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                        stderr=subprocess.STDOUT, text=True, bufsize=1,
                                        start_new_session=True)
        process, replies = self.process, self.replies

        def read():
            for line in process.stdout:
                self.logs.append(line.strip())
                if 'APPTRACER_READY ' in line:
                    replies.put({'ready': 'enabled=false' in line and 'backend=sentry-sdk' in line})
                elif 'APPTRACER_RESULT ' in line:
                    replies.put(json.loads(line.split('APPTRACER_RESULT ', 1)[1]))
        threading.Thread(target=read, daemon=True).start()
        self.wait(lambda: not replies.empty() or process.poll() is not None, 'ready')
        assert not replies.empty(), f'app exited before ready: {self.logs[-5:]}'
        assert replies.get_nowait() == {'ready': True}

    def command(self, action, expected=None, **values):
        identifier = len(self.steps)
        self.process.stdin.write(json.dumps(dict(id=identifier, action=action, **values)) + '\n')
        self.process.stdin.flush()
        if action == 'crash':
            result = self.process.wait(timeout=20)
            assert result != 0, result
            self.steps.append({'action': action, 'exit_code': result})
            return
        self.wait(lambda: not self.replies.empty(), action, timeout=20)
        result = self.replies.get_nowait()
        assert result.get('id') == identifier and 'error' not in result, result
        assert result['enabled'] == (result['state'] == 'enabled'), result
        if expected:
            assert result['state'] == expected, result
        self.steps.append(dict(action=action, **result))

    def quiet(self, index):
        time.sleep(2)
        assert len(self.requests) == index, self.requests[index:]
        assert self.process.poll() is None, self.logs[-5:]

    def terminate(self):
        if self.windows:
            if self.process is not None:
                if self.process.poll() is None:
                    self.process.terminate()
                self.process.wait(timeout=5)
                self.process = None
            from check_windows_runtime import cleanup_daemons
            cleanup_daemons(self.executable.parent)
            return
        if self.process is not None:
            # A dedicated session owns this probe and its Crashpad child only.
            try:
                os.killpg(self.process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            self.process.wait(timeout=5)
            self.process = None
        # Crashpad can detach from the runner's process group. End only handlers
        # from this unique relocated bundle; pin the PID before rechecking it.
        handlers = {str(self.executable.parent / suffix) for suffix in
                    ['crashpad_handler', 'bin/crashpad_handler', 'lib/crashpad_handler',
                     'sentry-crash', 'bin/sentry-crash', 'lib/sentry-crash']}
        for entry in Path('/proc').iterdir():
            if not entry.name.isdigit():
                continue
            descriptor = None
            try:
                if os.readlink(entry / 'exe') not in handlers:
                    continue
                descriptor = os.pidfd_open(int(entry.name))
                if os.readlink(entry / 'exe') in handlers:
                    signal.pidfd_send_signal(descriptor, signal.SIGKILL)
            except (FileNotFoundError, ProcessLookupError, PermissionError):
                pass
            finally:
                if descriptor is not None:
                    os.close(descriptor)

    def close(self):
        self.release_response.set()
        self.terminate()
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=2)


def lifecycle(p):
    p.launch()
    p.command('clear', 'disabled')
    p.quiet(0)
    p.command('start', 'enabled')
    p.command('start', 'enabled')
    p.command('identify', user='account-A')
    p.command('capture', message='before-stop-A')
    p.wait(lambda: len(p.requests) == 1, 'Dart event')
    p.command('stop', 'restartRequired')
    p.command('capture', message='forbidden-after-stop')
    p.command('start', 'restartRequired', preserve=True)
    p.command('clear', 'restartRequired')
    p.command('clear', 'restartRequired')
    assert (p.storage / 'revoked').is_file()
    assert (p.storage / 'queue').is_file() and (p.storage / 'queue').stat().st_size == 0
    p.quiet(1)
    p.command('crash')
    p.terminate()
    p.launch()
    p.quiet(1)
    p.command('start', 'enabled', preserve=True)
    p.quiet(1)
    p.command('identify', user='account-B')
    p.command('capture', message='fresh-account-B')
    p.wait(lambda: len(p.requests) == 2, 'new account')
    event = p.requests[-1]['events'][0]
    assert event['user']['id'] == 'account-B' and 'account-A' not in json.dumps(event)
    p.mode = 'hold'
    # Send without awaiting capture; stop must cancel the held HTTP transfer.
    identifier = len(p.steps)
    p.process.stdin.write(json.dumps({'id': identifier, 'action': 'capture-async', 'message': 'held'}) + '\n')
    p.process.stdin.flush()
    p.wait(lambda: not p.replies.empty(), 'async capture acknowledgement')
    assert p.replies.get_nowait().get('id') == identifier
    p.steps.append({'action': 'capture-async'})
    p.wait(lambda: len(p.requests) == 3, 'held Dart request')
    p.command('stop', 'restartRequired')
    p.wait(lambda: p.requests[-1].get('disconnected_before_response'), 'cancelled Dart socket', timeout=5)
    p.release_response.set()
    p.quiet(3)
    p.terminate()
    p.mode = 'online'
    p.launch()
    p.command('start', 'enabled', preserve=True)
    p.quiet(3)
    p.command('clear', 'restartRequired')


def check_metadata(event):
    os_context = event.get('contexts', {}).get('os', {})
    device = event.get('contexts', {}).get('device', {})
    assert os_context.get('name') and os_context.get('version'), os_context
    assert os_context.get('kernel_version') == Path('/proc/sys/kernel/osrelease').read_text().strip()
    assert device.get('arch') == 'x86_64', device
    assert not any(key in device for key in ('name', 'id', 'device_unique_identifier'))
    assert event.get('environment') == 'desktop-acceptance'
    assert event.get('release') == '1.0.0' and event.get('dist') == '1'


def grouping(p):
    p.launch()
    p.command('start', 'enabled')
    p.command('identify', user='group-account-A')
    for key in ['same-group', 'same-group', 'different-group']:
        p.command('capture', message='grouping acceptance', issueKey=key)
    p.wait(lambda: len(p.requests) == 3, 'three grouping events')
    events = [e for r in p.requests for e in r.get('events', [])]
    assert len(events) == 3 and len({e['event_id'] for e in events}) == 3
    assert [e['fingerprint'] for e in events] == [['same-group'], ['same-group'], ['different-group']]
    for event in events:
        check_metadata(event)
    p.quiet(3)
    p.command('clear', 'restartRequired')
    p.terminate()
    p.launch()
    p.command('start', 'enabled', preserve=True)
    p.command('identify', user='group-account-B')
    p.command('capture', message='grouping acceptance', issueKey='same-group')
    p.wait(lambda: len(p.requests) == 4, 'new account grouping event')
    event = p.requests[-1]['events'][0]
    assert event['user']['id'] == 'group-account-B'
    assert 'group-account-A' not in json.dumps(event)
    assert event['fingerprint'] == ['same-group']
    check_metadata(event)
    p.quiet(4)
    p.command('clear', 'restartRequired')


def native(p, policy='retry'):
    p.mode = 'disconnected'
    p.launch()
    p.command('start', 'enabled')
    p.command('identify', user='native-account')
    p.command('crash')
    p.wait(lambda: any('dump' in r for r in p.requests), 'rejected minidump')
    original = next(r for r in p.requests if 'dump' in r)
    assert original['path'] == '/api/42/envelope/'
    assert len(original['events']) == 1
    event = original['events'][0]
    check_metadata(event)
    assert event['platform'] == 'native' and event['user']['id'] == 'native-account'
    assert event['tags']['probe_run'] == p.env['TRACER_RUN_ID']
    assert any(e['type'] == 'SIGSEGV' and any(
        'apptracer_native_crash' in (f.get('function') or '')
        for f in e.get('stacktrace', {}).get('frames', []))
        for e in event.get('exception', {}).get('values', []))
    source_frames = [f for e in event['exception']['values']
                     for f in e.get('stacktrace', {}).get('frames', [])
                     if 'apptracer_native_crash' in (f.get('function') or '')]
    assert len(source_frames) == 1
    if p.expect_native_symbols:
        assert source_frames[0]['function'] == 'apptracer_native_crash()'
        assert source_frames[0].get('filename', '').endswith('/linux/runner/my_application.cc')
        assert source_frames[0].get('lineno') == 21
    else:
        assert not source_frames[0].get('filename') and not source_frames[0].get('lineno')
    rejected = [r['dump']['sha256'] for r in p.requests if 'dump' in r]
    time.sleep(1)
    p.terminate()
    p.mode = 'hold' if policy == 'inflight' else 'online'
    count = len(p.requests)
    p.launch()
    p.quiet(count)
    if policy == 'revoke':
        p.command('stop', 'disabled')
        p.terminate()
        p.launch()
    if policy in ('revoke', 'discard'):
        p.command('start', 'enabled', preserve=policy == 'revoke')
        p.quiet(count)
        p.command('clear', 'restartRequired')
        return
    p.command('start', 'enabled', preserve=True)
    p.wait(lambda: any('dump' in r for r in p.requests[count:]), 'retry after restart', timeout=60)
    delivered = [r['dump']['sha256'] for r in p.requests[count:] if 'dump' in r]
    assert len(delivered) == 1 and delivered[0] in rejected
    retry = next(r for r in p.requests[count:] if 'dump' in r)
    assert retry['events'][0]['event_id'] == event['event_id']
    assert retry['events'][0]['exception'] == event['exception']
    if policy == 'inflight':
        p.command('stop', 'restartRequired')
        p.wait(lambda: p.requests[-1].get('disconnected_before_response'), 'cancelled native socket', timeout=5)
    p.command('clear', 'restartRequired')


def dart_offline(p, policy='retry'):
    p.mode = 'disconnected'
    p.launch()
    p.command('start', 'enabled')
    p.command('identify', user='offline-account-A')
    marker = 'authorized-offline-dart'
    p.command('capture', message=marker)
    p.wait(lambda: any(marker in json.dumps(r.get('events', [])) for r in p.requests), 'rejected Dart envelope')

    def persisted():
        for path in (p.storage / 'queue').rglob('*'):
            try:
                if path.is_file() and marker.encode() in path.read_bytes():
                    return True
            except (FileNotFoundError, PermissionError):
                # Windows SDK lock files deny read sharing; wait for a readable
                # persisted envelope rather than treating a lock as payload.
                pass
        return False

    p.wait(persisted, 'Dart envelope persisted')
    if policy != 'online':
        p.terminate()
    p.mode = 'online'
    count = len(p.requests)
    if policy != 'online':
        p.launch()
        p.quiet(count)
        if policy == 'revoke':
            p.command('stop', 'disabled')
            p.terminate()
            p.launch()
        p.command('start', 'enabled', preserve=policy != 'discard')
    if policy in ('retry', 'online'):
        p.wait(lambda: any(marker in json.dumps(r.get('events', [])) for r in p.requests[count:]),
               'Dart retry', timeout=950 if policy == 'online' else 60)
        events = [e for r in p.requests[count:] for e in r.get('events', [])]
        assert len(events) == 1 and events[0]['user']['id'] == 'offline-account-A'
        original = next(e for r in p.requests[:count] for e in r.get('events', [])
                        if marker in json.dumps(e))
        assert events[0]['event_id'] == original['event_id']
        assert events[0]['exception'] == original['exception']
    else:
        p.quiet(count)
    p.command('clear', 'restartRequired')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', required=True, type=Path)
    parser.add_argument('--scenario', required=True, choices=[
        'lifecycle', 'grouping', 'native', 'native-revoked', 'native-discard', 'native-inflight',
        'dart-retry', 'dart-online', 'dart-revoked', 'dart-discard',
        'missing-handler', 'unwritable-storage', 'readonly-bundle',
        'missing-native-symbols', 'mismatched-native-symbols'])
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--dump-directory', type=Path,
                        help='optionally preserve this synthetic native dump for local symbolication')
    args = parser.parse_args()
    report = {'scenario': args.scenario, 'failures': [],
              'scope': 'Ubuntu loopback only; no Tracer console acceptance'}
    with tempfile.TemporaryDirectory(prefix='apptracer-linux-') as temp:
        directory = Path(temp)
        bundle = directory / 'Release Кириллица'
        shutil.copytree(args.app.resolve(), bundle, symlinks=True)
        p = Probe(bundle, directory, args.dump_directory)
        try:
            if args.scenario in ('missing-native-symbols', 'mismatched-native-symbols'):
                symbols = list((bundle / 'lib/symbols/apptracer_desktop_example').glob('*/*.sym'))
                assert len(symbols) == 1
                if args.scenario == 'missing-native-symbols':
                    symbols[0].unlink()
                else:
                    data = symbols[0].read_text()
                    header, rest = data.split('\n', 1)
                    fields = header.split()
                    fields[3] = '0' * 33
                    symbols[0].write_text(' '.join(fields) + '\n' + rest)
                p.expect_native_symbols = False
                native(p)
            elif args.scenario == 'missing-handler':
                # Sentry's own install rules also place a copy in bin/.
                for candidate in ['sentry-crash', 'bin/sentry-crash', 'lib/sentry-crash']:
                    (bundle / candidate).unlink(missing_ok=True)
                p.launch()
                p.command('start', 'error')
                p.quiet(0)
            elif args.scenario == 'unwritable-storage':
                # ENOTDIR is deterministic even in privileged CI containers.
                (directory / 'Data Кириллица').write_text('not a directory')
                p.launch()
                p.command('start', 'error')
                p.quiet(0)
            elif args.scenario == 'readonly-bundle':
                for path in [bundle, *bundle.rglob('*')]:
                    if not path.is_symlink():
                        path.chmod(path.stat().st_mode & ~0o222)
                p.launch()
                p.command('start', 'enabled')
                p.command('capture', message='readonly-install')
                p.wait(lambda: len(p.requests) == 1, 'readonly bundle event')
                p.command('clear', 'restartRequired')
            elif args.scenario == 'grouping':
                grouping(p)
            elif args.scenario.startswith('native'):
                native(p, {'native-revoked': 'revoke', 'native-discard': 'discard', 'native-inflight': 'inflight'}.get(args.scenario, 'retry'))
            elif args.scenario.startswith('dart-'):
                dart_offline(p, {'dart-revoked': 'revoke', 'dart-discard': 'discard', 'dart-online': 'online'}.get(args.scenario, 'retry'))
            else:
                lifecycle(p)
            assert not any('error' in r for r in p.requests), p.requests
        except Exception as error:
            report['failures'].append(repr(error))
        finally:
            p.close()
            if args.scenario == 'readonly-bundle':
                for path in [bundle, *bundle.rglob('*')]:
                    if path.is_dir() and not path.is_symlink():
                        path.chmod(path.stat().st_mode | 0o700)
            report.update(steps=p.steps, requests=p.requests, logs=p.logs[-20:])
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'scenario': args.scenario, 'steps': len(report['steps']), 'failures': report['failures']}))
    return bool(report['failures'])


if __name__ == '__main__':
    raise SystemExit(main())
