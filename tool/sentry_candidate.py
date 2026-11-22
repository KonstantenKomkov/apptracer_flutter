#!/usr/bin/env python3
"""Select an exact Sentry candidate and identify the SDKs in a desktop build."""
import argparse
import json
import os
import platform
import re
import subprocess
import urllib.request
from pathlib import Path

DESKTOP = Path('packages/apptracer_flutter_desktop')
EXAMPLE = DESKTOP / 'example'
PIN = re.compile(r'^(  sentry_flutter: )([^\s#]+)$', re.MULTILINE)
VERSION = re.compile(r'[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?')


def select_version(requested):
    if not requested:
        with urllib.request.urlopen('https://pub.dev/api/packages/sentry_flutter', timeout=30) as response:
            requested = json.load(response)['latest']['version']
    if not VERSION.fullmatch(requested):
        raise ValueError('Expected an exact sentry_flutter version')
    return requested


def apply_version(path, version):
    if not VERSION.fullmatch(version):
        raise ValueError('Expected an exact sentry_flutter version')
    contents = path.read_text()
    matches = PIN.findall(contents)
    if len(matches) != 1 or not VERSION.fullmatch(matches[0][1]):
        raise ValueError('Expected one exact sentry_flutter production pin')
    path.write_text(PIN.sub(lambda m: m[1] + version, contents))


def build_evidence(version):
    lock = (EXAMPLE / 'pubspec.lock').read_text()
    resolved = re.search(r'^  sentry_flutter:\n(?:    [^\n]*\n)*?    version: "([^"]+)"$', lock, re.M)
    if not resolved or resolved[1] != version:
        raise ValueError('Release example resolved a different sentry_flutter version')

    system = platform.system()
    if system == 'Darwin':
        pods = (EXAMPLE / 'macos/Podfile.lock').read_text()
        cocoa = re.search(r'^  - Sentry/HybridSDK \(([^)]+)\)', pods, re.M)
        if not cocoa:
            raise ValueError('Sentry Cocoa version missing from Podfile.lock')
        native = {'sentryCocoa': cocoa[1]}
    else:
        if system == 'Windows':
            deps = Path(os.environ['RUNNER_TEMP']) / 'tracer-native'
        else:
            deps = EXAMPLE / 'build/linux/x64/release/_deps'
        source = deps / 'sentry-native-src'
        if not (source / '.git').exists():
            raise ValueError(f'Cannot identify compiled sentry-native checkout at {source}')
        native = {'sentryNative': subprocess.check_output(
            ['git', '-C', str(source), 'describe', '--tags', '--always'], text=True).strip()}
    # flutter is a .bat launcher on Windows.
    flutter = 'flutter.bat' if system == 'Windows' else 'flutter'
    toolchain = json.loads(subprocess.check_output([flutter, '--version', '--machine'], text=True))
    return {'sentryFlutter': version, **native, 'os': platform.platform(),
            'flutter': toolchain['frameworkVersion'], 'dart': toolchain['dartSdkVersion']}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['select', 'apply', 'evidence'])
    args = parser.parse_args()
    version = os.environ.get('SENTRY_CANDIDATE', '')
    if args.command == 'apply':
        apply_version(DESKTOP / 'pubspec.yaml', version)
        return
    if args.command == 'select':
        if os.environ.get('GITHUB_EVENT_NAME') == 'pull_request':
            version = PIN.search((DESKTOP / 'pubspec.yaml').read_text())[2]
        name, value = 'version', select_version(version)
    else:
        name, value = 'versions', json.dumps(build_evidence(version))
    print(value)
    with open(os.environ['GITHUB_OUTPUT'], 'a', encoding='utf-8') as output:
        print(f'{name}={value}', file=output)


if __name__ == '__main__':
    main()
