#!/usr/bin/env python3
"""Check automatic Dart source display and safe fallback in a release bundle."""
import argparse
import gzip
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


def validate(report, resolved):
    expected = {'desktop handled probe': ('_handled', 45),
                'desktop FlutterError probe': ('_flutterError', 55),
                'desktop async probe': ('_asyncError', 64)}
    assert not report['failures'] and len(report['events']) == 3
    for marker, (function, line) in expected.items():
        event = next(e for e in report['events'] if marker in str(e['exception']))
        frames = [f for e in event['exception']['values'] for f in e['stacktrace']['frames']]
        assert event['contexts']['apptracer']['dart_stack_trace']
        if resolved:
            assert any(function in (f.get('function') or '') and
                       f.get('filename', '').endswith('/example/lib/main.dart') and
                       f.get('lineno') == line for f in frames), (marker, frames)
        else:
            assert all(not f.get('filename') and not f.get('lineno') for f in frames)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', required=True, type=Path)
    parser.add_argument('--mode', choices=['resolved', 'missing', 'mismatched'], default='resolved')
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='apptracer-dart-display-') as temp:
        bundle = Path(temp) / 'Release Кириллица'
        shutil.copytree(args.app, bundle, symlinks=True)
        maps = list((bundle / 'lib/apptracer-dart-symbols').glob('*.json.gz'))
        assert len(maps) == 1
        if args.mode == 'missing':
            maps[0].unlink()
        elif args.mode == 'mismatched':
            value = json.loads(gzip.decompress(maps[0].read_bytes()))
            value['build_id'] = '0' * 32
            maps[0].write_bytes(gzip.compress(json.dumps(value).encode(), mtime=0))
        subprocess.run([sys.executable, str(Path(__file__).with_name('check_linux_desktop.py')),
                        '--app', str(bundle), '--scenario', 'smoke',
                        '--output', str(args.output)], check=True)
        report = json.loads(args.output.read_text(encoding='utf-8'))
        try:
            validate(report, args.mode == 'resolved')
        except AssertionError:
            report['failures'].append('Dart source frame validation failed: ' + args.mode)
            raise
        finally:
            report['dart_display_mode'] = args.mode
            args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'dart_display': args.mode, 'passed': True}))


if __name__ == '__main__':
    main()
