#!/usr/bin/env python3
"""Windows native-backend lifecycle acceptance against an isolated loopback server."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from check_linux_runtime import Probe, dart_offline, lifecycle


def cleanup_daemons(bundle):
    # Open a stable process handle before checking the unique probe image path.
    target = str((bundle / 'sentry-crash.exe').resolve()).replace("'", "''")
    script = (
        "$ErrorActionPreference='Stop'; "
        "Get-Process -Name 'sentry-crash' -ErrorAction SilentlyContinue | ForEach-Object { "
        "$candidate=$_; try { $handle=$candidate.Handle; "
        f"if ($candidate.MainModule.FileName -eq '{target}') {{ $candidate.Kill(); "
        "if (-not $candidate.WaitForExit(5000)) { throw 'daemon timeout' } } "
        "} catch { if (-not $candidate.HasExited) { throw } } }; exit 0"
    )
    subprocess.run(['powershell.exe', '-NoProfile', '-Command', script],
                   capture_output=True, timeout=20, check=True)


def native(p, policy):
    p.mode = 'disconnected'
    p.launch()
    p.command('start', 'enabled')
    p.command('identify', user='windows-native-A')
    p.command('crash')
    p.wait(lambda: any('dump' in r for r in p.requests), 'native envelope')
    original = next(r for r in p.requests if 'dump' in r)
    assert original['path'] == '/api/42/envelope/'
    event = original['events'][0]
    assert event['platform'] == 'native'
    assert event['user']['id'] == 'windows-native-A'
    assert event['tags']['probe_run'] == p.env['TRACER_RUN_ID']
    assert event['exception']['values']
    source = [f for ex in event['exception']['values']
              for f in ex.get('stacktrace', {}).get('frames', [])
              if 'ApptracerNativeCrashProbe' in f.get('function', '')]
    assert len(source) == 1 and source[0]['trust'] == 'context', source
    if p.expect_native_symbols:
        assert source[0]['filename'].replace('\\', '/').endswith('/windows/runner/flutter_window.cpp')
        assert source[0]['lineno'] == 16
    else:
        assert not source[0].get('filename') and not source[0].get('lineno')
    p.terminate()
    count = len(p.requests)
    p.mode = 'hold' if policy == 'inflight' else 'online'
    p.launch()
    p.quiet(count)
    if policy == 'revoke':
        p.command('stop', 'disabled')
        p.terminate()
        p.launch()
    p.command('start', 'enabled', preserve=policy != 'discard')
    if policy in ('revoke', 'discard'):
        p.quiet(count)
    else:
        p.wait(lambda: any('dump' in r for r in p.requests[count:]), 'native retry', timeout=60)
        retried = [r for r in p.requests[count:] if 'dump' in r]
        assert len(retried) == 1
        assert retried[0]['dump']['sha256'] == original['dump']['sha256']
        assert retried[0]['events'][0]['event_id'] == event['event_id']
        if policy == 'inflight':
            p.command('stop', 'restartRequired')
            p.wait(lambda: retried[0].get('disconnected_before_response'), 'cancelled native upload', timeout=5)
    p.command('clear', 'restartRequired')


def grouping(p):
    p.launch()
    p.command('start', 'enabled')
    p.command('identify', user='windows-account-A')
    for key in ['same-group', 'same-group', 'different-group']:
        p.command('capture', message='Windows grouping probe', issueKey=key)
    p.wait(lambda: len(p.requests) == 3, 'grouping events')
    events = [r['events'][0] for r in p.requests]
    assert len({e['event_id'] for e in events}) == 3
    assert [e['fingerprint'] for e in events] == [['same-group'], ['same-group'], ['different-group']]
    p.command('clear', 'restartRequired')
    p.terminate()
    p.launch()
    p.command('start', 'enabled', preserve=True)
    p.command('identify', user='windows-account-B')
    p.command('capture', message='Windows grouping probe', issueKey='same-group')
    p.wait(lambda: len(p.requests) == 4, 'second account')
    event = p.requests[-1]['events'][0]
    assert event['user']['id'] == 'windows-account-B'
    assert 'windows-account-A' not in json.dumps(event)
    assert event['fingerprint'] == ['same-group']
    p.command('clear', 'restartRequired')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--dump-directory', type=Path)
    parser.add_argument('--scenario', required=True, choices=[
        'lifecycle', 'grouping', 'native', 'native-revoked', 'native-discard',
        'native-inflight', 'dart-retry', 'dart-online', 'dart-revoked',
        'dart-discard', 'missing-handler', 'unwritable-storage',
        'missing-native-symbols', 'mismatched-native-symbols', 'junction-storage',
        'concurrent-owner', 'readonly-bundle', 'junction-queue-entry'])
    args = parser.parse_args()
    if os.name != 'nt':
        parser.error('run on Windows x64')
    report = {'scenario': args.scenario, 'failures': [],
              'scope': 'Windows loopback only; not Tracer dashboard acceptance'}
    with tempfile.TemporaryDirectory(prefix='apptracer-windows-') as temp:
        directory = Path(temp)
        bundle = directory / 'Release Кириллица'
        shutil.copytree(args.app.resolve(), bundle)
        p = Probe(bundle, directory, args.dump_directory, windows=True)
        denied_sid = None
        try:
            if args.scenario in ('missing-native-symbols', 'mismatched-native-symbols'):
                symbols = list((bundle / 'symbols/apptracer_desktop_example.pdb').glob('*/*.sym'))
                assert len(symbols) == 1
                if args.scenario == 'missing-native-symbols':
                    symbols[0].unlink()
                else:
                    header, rest = symbols[0].read_text(encoding='utf-8').split('\n', 1)
                    fields = header.split()
                    fields[3] = '0' * 33
                    symbols[0].write_text(' '.join(fields) + '\n' + rest, encoding='utf-8')
                p.expect_native_symbols = False
                native(p, 'retry')
            elif args.scenario == 'junction-storage':
                target = directory / 'unrelated'
                target.mkdir()
                sentinel = target / 'keep.txt'
                sentinel.write_text('unrelated data', encoding='utf-8')
                link = directory / 'Data Кириллица'
                # Fixed, quoted paths inside this unique temporary directory.
                quote = lambda value: str(value).replace("'", "''")
                subprocess.run(['powershell.exe', '-NoProfile', '-Command',
                                f"New-Item -ItemType Junction -Path '{quote(link)}' -Target '{quote(target)}' | Out-Null"], check=True)
                p.launch()
                p.command('start', 'error')
                p.quiet(0)
                assert sentinel.read_text(encoding='utf-8') == 'unrelated data'
                assert list(target.iterdir()) == [sentinel]
            elif args.scenario == 'readonly-bundle':
                denied_sid = subprocess.check_output([
                    'powershell.exe', '-NoProfile', '-Command',
                    '[System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value'],
                    text=True).strip()
                subprocess.run(['icacls.exe', str(bundle), '/deny',
                                f'*{denied_sid}:(OI)(CI)(WD,AD,WEA,WA)'], capture_output=True, check=True)
                try:
                    (bundle / 'forbidden-write.txt').write_bytes(b'fail')
                except PermissionError:
                    pass
                else:
                    raise AssertionError('bundle ACL did not prevent writes')
                p.launch()
                p.command('start', 'enabled')
                p.command('capture', message='readonly-install')
                p.wait(lambda: len(p.requests) == 1, 'readonly bundle event')
                p.command('clear', 'restartRequired')
            elif args.scenario == 'junction-queue-entry':
                target = directory / 'unrelated'
                target.mkdir()
                sentinel = target / 'keep.txt'
                sentinel.write_text('unrelated data', encoding='utf-8')
                p.launch()
                p.command('start', 'enabled')
                link = p.storage / 'queue' / 'unrelated-junction'
                quote = lambda value: str(value).replace("'", "''")
                subprocess.run(['powershell.exe', '-NoProfile', '-Command',
                                f"New-Item -ItemType Junction -Path '{quote(link)}' -Target '{quote(target)}' | Out-Null"], check=True)
                p.command('clear', 'restartRequired')
                assert sentinel.read_text(encoding='utf-8') == 'unrelated data'
            elif args.scenario == 'concurrent-owner':
                p.launch()
                p.command('start', 'enabled')
                second = Probe(bundle, directory, windows=True)
                try:
                    second.launch()
                    second.command('start', 'error')
                    second.quiet(0)
                    p.command('capture', message='original owner still active')
                    p.wait(lambda: len(p.requests) == 1, 'owner event')
                    # Do not call second.close(): its cleanup targets this shared
                    # bundle's daemon. Only the first owner may close it here.
                finally:
                    if second.process is not None:
                        second.process.terminate()
                        second.process.wait(timeout=5)
                    second.server.shutdown()
                    second.server.server_close()
                    second.thread.join(timeout=2)
                p.command('clear', 'restartRequired')
            elif args.scenario == 'missing-handler':
                (bundle / 'sentry-crash.exe').unlink()
                p.launch()
                p.command('start', 'error')
                p.quiet(0)
            elif args.scenario == 'unwritable-storage':
                (directory / 'Data Кириллица').write_text('not a directory')
                p.launch()
                p.command('start', 'error')
                p.quiet(0)
            elif args.scenario == 'grouping':
                grouping(p)
            elif args.scenario.startswith('native'):
                native(p, {'native-revoked': 'revoke', 'native-discard': 'discard',
                           'native-inflight': 'inflight'}.get(args.scenario, 'retry'))
            elif args.scenario.startswith('dart-'):
                dart_offline(p, {'dart-revoked': 'revoke', 'dart-discard': 'discard',
                                'dart-online': 'online'}.get(args.scenario, 'retry'))
            else:
                lifecycle(p)
            assert not any('error' in r for r in p.requests), p.requests
        except Exception as error:
            report['failures'].append(repr(error))
        finally:
            report['daemon_logs'] = {
                str(path.relative_to(p.storage)): path.read_text(encoding='utf-8', errors='replace')[-16000:]
                for path in p.storage.rglob('*.log') if path.is_file()
            }
            report['queue_files'] = [str(path.relative_to(p.storage))
                                     for path in p.storage.rglob('*') if path.is_file()]
            p.close()
            if denied_sid:
                subprocess.run(['icacls.exe', str(bundle), '/remove:d',
                                f'*{denied_sid}'], capture_output=True, check=True)
            report.update(steps=p.steps, requests=p.requests, logs=p.logs[-30:])
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'scenario': args.scenario, 'steps': len(report['steps']), 'failures': report['failures']}))
    return bool(report['failures'])


if __name__ == '__main__':
    raise SystemExit(main())
