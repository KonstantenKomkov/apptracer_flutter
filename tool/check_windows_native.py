#!/usr/bin/env python3
"""Crash only a relocated release example; validate its native dump via loopback.

No Tracer credentials are read. This checks native capture/delivery and a fresh
process restart, not server symbolication or collection revocation.
"""
import argparse
from email.parser import BytesParser
from email import policy
import gzip
import hashlib
import json
import os
from pathlib import Path
import queue
import shutil
import struct
import subprocess
import tempfile
import threading
import time
import urllib.parse
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from check_macos_desktop import read_http_body


def span(data, offset, size):
    if offset < 0 or size < 0 or offset + size > len(data):
        raise ValueError('truncated binary record')
    return data[offset:offset + size]


def u32(data, offset):
    return struct.unpack('<I', span(data, offset, 4))[0]


def codeview(data):
    if span(data, 0, 4) != b'RSDS':
        raise ValueError('missing PDB 7 CodeView identity')
    return {'guid': str(uuid.UUID(bytes_le=bytes(span(data, 4, 16)))), 'age': u32(data, 20)}


def pe_identity(data):
    if span(data, 0, 2) != b'MZ':
        raise ValueError('not a PE image')
    pe = u32(data, 0x3c)
    if span(data, pe, 4) != b'PE\0\0':
        raise ValueError('invalid PE header')
    sections = struct.unpack('<H', span(data, pe + 6, 2))[0]
    optional_size = struct.unpack('<H', span(data, pe + 20, 2))[0]
    optional = pe + 24
    if span(data, optional, 2) != b'\x0b\x02':
        raise ValueError('expected a PE32+ x64 runner')
    debug_rva, debug_size = struct.unpack('<II', span(data, optional + 112 + 6 * 8, 8))
    section_table = optional + optional_size
    for index in range(sections):
        section = section_table + index * 40
        virtual_size, virtual_address, raw_size, raw_offset = struct.unpack('<IIII', span(data, section + 8, 16))
        if virtual_address <= debug_rva < virtual_address + max(virtual_size, raw_size):
            offset = raw_offset + debug_rva - virtual_address
            for entry in range(0, debug_size, 28):
                record = span(data, offset + entry, 28)
                if u32(record, 12) == 2:
                    return codeview(span(data, u32(record, 24), u32(record, 16)))
    raise ValueError('runner has no CodeView record')


def inspect_dump(data, executable_name):
    if span(data, 0, 4) != b'MDMP':
        raise ValueError('not a minidump')
    count, directory = u32(data, 8), u32(data, 12)
    if count > 1000:
        raise ValueError('invalid stream count')
    exception = None
    module = None
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
                if name.replace('\\', '/').split('/')[-1].lower() == executable_name.lower():
                    identity = codeview(span(data, u32(record, 80), u32(record, 76)))
                    module = {'path': name, 'codeview': identity}
    if exception is None or module is None:
        raise ValueError('minidump is missing runner module or exception stream')
    return {'sha256': hashlib.sha256(data).hexdigest(), 'bytes': len(data),
            'exception_code': f'0x{exception:08x}', 'runner': module}


def multipart_dumps(content_type, body):
    message = BytesParser(policy=policy.default).parsebytes(
        b'Content-Type: ' + content_type.encode('ascii') + b'\r\nMIME-Version: 1.0\r\n\r\n' + body)
    if not message.is_multipart() or message.defects:
        raise ValueError('invalid multipart upload')
    parts = []
    for part in message.iter_parts():
        payload = part.get_payload(decode=True)
        if payload and payload[:4] == b'MDMP':
            parts.append(payload)
    if len(parts) != 1:
        raise ValueError('expected exactly one minidump attachment')
    return parts[0]


def cleanup_handlers(bundle):
    # Only the unique relocated probe's executable and registry value are touched.
    handler = str(bundle / 'crashpad_handler.exe').replace("'", "''")
    wer = str(bundle / 'crashpad_wer.dll').replace("'", "''")
    script = (
        "$ErrorActionPreference = 'Stop'; "
        "Get-CimInstance Win32_Process -Filter \"Name='crashpad_handler.exe'\" | "
        f"Where-Object {{ $_.ExecutablePath -eq '{handler}' }} | "
        "ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction Stop }; "
        "if (Get-CimInstance Win32_Process -Filter \"Name='crashpad_handler.exe'\" | "
        f"Where-Object {{ $_.ExecutablePath -eq '{handler}' }}) {{ throw 'Probe handler still running' }}; "
        "Remove-ItemProperty -LiteralPath 'HKCU:\\Software\\Microsoft\\Windows\\Windows Error Reporting\\RuntimeExceptionHelperModules' "
        f"-Name '{wer}' -ErrorAction SilentlyContinue; exit 0")
    result = subprocess.run(['powershell.exe', '-NoProfile', '-Command', script],
                            capture_output=True, timeout=20, check=False)
    if result.returncode != 0:
        raise RuntimeError('could not confirm probe Crashpad cleanup')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--dump-dir', type=Path,
                        help='Keep only this probe\'s validated minidumps for local symbol checks')
    parser.add_argument('--offline-restart', action='store_true',
                        help='Reject the initial upload with 503; stop the old handler before restart')
    args = parser.parse_args()
    if os.name != 'nt':
        parser.error('run on Windows x64')
    name = 'apptracer_desktop_example.exe'
    identity = pe_identity((args.app / name).read_bytes())
    incoming = queue.Queue()
    phase = 'offline-crash' if args.offline_restart else 'crash'
    requests = []
    failures = []
    dumps = []
    ready = []
    exit_code = None
    process = None

    class Receiver(BaseHTTPRequestHandler):
        def log_message(self, *unused):
            pass

        def do_POST(self):
            try:
                request_phase = phase
                body = read_http_body(self.rfile, self.headers)
                if self.headers.get('Content-Encoding') == 'gzip':
                    body = gzip.decompress(body)
                dump = multipart_dumps(self.headers.get('Content-Type', ''), body)
                accepted = request_phase != 'offline-crash'
                request = {'path': self.path, 'phase': request_phase,
                           'accepted': accepted, 'dump': inspect_dump(dump, name)}
                if args.dump_dir:
                    if request['dump']['runner']['codeview'] != identity:
                        raise ValueError('refusing to retain a dump from another build')
                    if run_id not in request['dump']['runner']['path']:
                        raise ValueError('refusing to retain a dump from another run')
                    args.dump_dir.mkdir(parents=True, exist_ok=True)
                    (args.dump_dir / (request['dump']['sha256'] + '.dmp')).write_bytes(dump)
                self.send_response(200 if accepted else 503)
                self.send_header('Content-Length', '2')
                self.end_headers()
                self.wfile.write(b'{}')
                incoming.put(request)
            except Exception as error:
                incoming.put({'path': self.path, 'phase': phase,
                              'error': type(error).__name__ + ': ' + str(error)})
                self.send_error(400)

    server = ThreadingHTTPServer(('127.0.0.1', 0), Receiver)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    run_id = uuid.uuid4().hex
    try:
        with tempfile.TemporaryDirectory(prefix='apptracer-native-') as directory:
            bundle = Path(directory) / ('Native probe Кириллица ' + run_id)
            shutil.copytree(args.app.resolve(), bundle)
            # Artifacts should be clean. Refuse accidental restoration of someone else's queue.
            if (bundle / '.sentry-native').exists():
                raise ValueError('release artifact unexpectedly contains a native SDK database')
            status = Path(directory) / 'ready.txt'
            env = dict(os.environ, TRACER_WINDOWS_SENTRY_DSN=f'http://local-native@127.0.0.1:{server.server_port}/42',
                       TRACER_RUN_ID=run_id, TRACER_PROBE_READY_FILE=str(status),
                       TRACER_PRESERVE_REPORTS='true')

            def launch(scenario):
                status.unlink(missing_ok=True)
                return subprocess.Popen([str(bundle / name)], cwd=bundle,
                                        env=dict(env, TRACER_SCENARIO=scenario),
                                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

            def await_ready():
                deadline = time.monotonic() + 20
                while time.monotonic() < deadline:
                    if status.exists():
                        text = status.read_text(encoding='utf-8')
                        if 'state=enabled' in text and 'enabled=true' in text:
                            ready.append(phase)
                            return
                        if 'state=' in text:
                            raise ValueError('native SDK did not enable: ' + text)
                    if process.poll() is not None:
                        raise ValueError('application exited before readiness')
                    time.sleep(0.1)
                raise ValueError('application readiness timeout')

            try:
                process = launch('native-crash')
                await_ready()
                exit_code = process.wait(timeout=30)
                if exit_code == 0:
                    failures.append('native crash exited successfully')
                if args.offline_restart:
                    rejected = incoming.get(timeout=30)
                    requests.append(rejected)
                    if rejected.get('accepted') is not False or 'error' in rejected:
                        raise ValueError('initial native upload was not rejected with 503')
                    # Let the handler process the response, then stop that exact
                    # relocated handler. Only the next process may retry online.
                    time.sleep(1)
                    cleanup_handlers(bundle)
                phase = 'restart'
                process = launch('idle')
                await_ready()
                deadline = time.monotonic() + 45
                settled = None
                while time.monotonic() < deadline:
                    try:
                        request = incoming.get(timeout=0.1)
                        requests.append(request)
                        if urllib.parse.urlparse(request['path']).path != '/api/42/minidump/':
                            failures.append('unexpected native ingest path')
                        if 'error' in request:
                            failures.append(request['error'])
                        else:
                            dump = request['dump']
                            if request.get('accepted'):
                                dumps.append(dump)
                            if dump['exception_code'] != '0xc0000005':
                                failures.append('unexpected native exception code')
                            if dump['runner']['codeview'] != identity:
                                failures.append('minidump does not match the release runner')
                            if run_id not in dump['runner']['path']:
                                failures.append('minidump belongs to a different probe directory')
                            if request.get('accepted'):
                                settled = time.monotonic() + 5
                    except queue.Empty:
                        pass
                    if process.poll() is not None:
                        failures.append('restarted app exited unexpectedly')
                        break
                    if settled and time.monotonic() >= settled:
                        break
                if len(dumps) != 1:
                    failures.append(f'expected one native minidump, got {len(dumps)}')
                elif args.offline_restart:
                    rejected_hashes = {item['dump']['sha256'] for item in requests
                                       if item.get('accepted') is False and 'dump' in item}
                    if dumps[0]['sha256'] not in rejected_hashes:
                        failures.append('retry did not preserve the rejected minidump')
            except Exception as error:
                failures.append(type(error).__name__ + ': ' + str(error))
            finally:
                if process and process.poll() is None:
                    process.terminate()
                    process.wait(timeout=5)
                cleanup_handlers(bundle)
    except Exception as error:
        failures.append(type(error).__name__ + ': ' + str(error))
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)
    report = {'run_id': run_id, 'offline_restart': args.offline_restart,
              'ready': ready, 'crash_exit_code': exit_code,
              'runner_codeview': identity, 'requests': requests, 'failures': failures,
              'scope': 'native capture + loopback + restart; optional HTTP 503 recovery; no Tracer acceptance, symbolication or revocation'}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    # Windows CI can expose a cp1252 stdout even when files use UTF-8.
    print(json.dumps(report))
    return 1 if failures else 0


if __name__ == '__main__':
    raise SystemExit(main())
