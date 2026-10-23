#!/usr/bin/env python3
"""Verify real obfuscated macOS errors, their symbols and local source locations.

Build the desktop example with --obfuscate --split-debug-info first. This probe
archives the exact .app and symbols, runs the existing loopback smoke check,
and decodes all three raw stacks. It does not send anything to Tracer.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

from symbolize_macos_dart import decoded_text, macho_uuids, normalized_id, symbolize


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, required=True)
    parser.add_argument('--symbols', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    # Keep evidence from earlier builds; callers must choose a new directory.
    output.mkdir(parents=True, exist_ok=False)
    app = args.app.resolve()
    image = app / 'Contents/Frameworks/App.framework/App'
    report = {'scope': 'macOS Dart AOT loopback + local atos; no Tracer console acceptance',
              'success': False, 'events': [], 'symbols': []}
    env = {key: value for key, value in os.environ.items() if not key.startswith('TRACER_')}
    try:
        image_ids = macho_uuids(image)
        report['app_image'] = {'sha256': sha256(image), 'uuids': image_ids}
        report['flutter'] = subprocess.check_output(['flutter', '--version'], env=env, text=True)
        report['os'] = subprocess.check_output(['sw_vers'], text=True)
        report['xcode'] = subprocess.check_output(['xcodebuild', '-version'], text=True)
        by_arch = {}
        symbol_dir = output / 'symbols'
        symbol_dir.mkdir()
        for path in sorted(args.symbols.glob('app.darwin-*.symbols')):
            ids = macho_uuids(path)
            if len(ids) != 1:
                raise ValueError('expected one architecture per Dart symbols file')
            arch, identity = next(iter(ids.items()))
            if arch in by_arch or image_ids.get(arch) != identity:
                raise ValueError('duplicate or foreign symbols: ' + path.name)
            copied = symbol_dir / path.name
            shutil.copy2(path, copied)
            by_arch[arch] = copied
            report['symbols'].append({'path': str(copied.relative_to(output)),
                                      'sha256': sha256(copied), 'uuids': ids})
        if set(by_arch) != set(image_ids):
            raise ValueError('missing symbols for an App.framework architecture')
        subprocess.run(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent',
                        str(app), str(output / 'release.zip')], check=True)
        report['release_zip_sha256'] = sha256(output / 'release.zip')
        subprocess.run([sys.executable, str(Path(__file__).with_name('check_macos_desktop.py')),
                        '--app', str(app), '--scenario', 'smoke',
                        '--output', str(output / 'smoke.json')], env=env, check=True)
        smoke = json.loads((output / 'smoke.json').read_text())
        expected = {'desktop handled probe': 'handled',
                    'desktop FlutterError probe': 'flutterError',
                    'desktop async probe': 'asyncError'}
        for index, event in enumerate(smoke['events']):
            raw = event['contexts']['apptracer']['dart_stack_trace']
            value = event['exception']['values'][0]['value']
            marker = next(marker for marker in expected if marker in value)
            raw_file = output / f'{index}-raw.txt'
            raw_file.write_text(raw, encoding='utf-8')
            # Architecture is checked again against the raw stack inside symbolize.
            arch = 'arm64' if 'arch: arm64 ' in raw else 'x86_64'
            result = symbolize(raw, by_arch[arch], image)
            images = event.get('debug_meta', {}).get('images', [])
            if not any(normalized_id(item['debug_id']) == result['build_id']
                       for item in images if item.get('type') == 'macho'):
                raise ValueError('SDK debug image does not match the Dart stack')
            first = result['frames'][0]['symbol']
            if expected.pop(marker) not in first or '(main.dart:' not in first:
                raise ValueError('first frame did not recover the expected source location')
            (output / f'{index}-decoded.txt').write_text(decoded_text(result), encoding='utf-8')
            # Keep the stock Flutter command's actual result separately. Its
            # exit status does not replace the verified atos source locations.
            with (output / f'{index}-flutter-symbolize.log').open('w') as log:
                flutter = subprocess.run(['flutter', 'symbolize', '-i', str(raw_file),
                                          '-d', str(by_arch[arch])], env=env,
                                         stdout=log, stderr=subprocess.STDOUT, timeout=60)
            report['events'].append({'event_id': event['event_id'], 'marker': marker,
                                     'flutter_symbolize_exit': flutter.returncode, **result})
        if expected or len(report['events']) != 3:
            raise ValueError('missing or duplicated scenario')
        if sha256(image) != report['app_image']['sha256']:
            raise ValueError('App.framework changed during acceptance')
        report['success'] = True
    except Exception as error:
        report['error'] = str(error)
    finally:
        (output / 'report.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'success': report['success'], 'report': str(output / 'report.json'),
                      'error': report.get('error')}))
    return 0 if report['success'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
