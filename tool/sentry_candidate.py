#!/usr/bin/env python3
"""Select an exact Sentry candidate and identify the SDKs in a desktop build."""
import argparse
import ctypes
import hashlib
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


def cocoa_evidence(app):
    package = app / 'macos/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved'
    pins = json.loads(package.read_text())['pins']
    cocoa = next(pin for pin in pins if pin['identity'] == 'sentry-apple-binaries')
    checkout = app / 'build/macos/SourcePackages/checkouts/sentry-apple-binaries'
    revision = subprocess.check_output(['git', '-C', str(checkout), 'rev-parse', 'HEAD'],
                                       text=True).strip()
    tag_revision = subprocess.check_output(
        ['git', '-C', str(checkout), 'rev-parse', f"refs/tags/{cocoa['state']['version']}^{{commit}}"],
        text=True).strip()
    if revision != cocoa['state']['revision'] or tag_revision != revision:
        raise ValueError('Compiled Sentry Cocoa checkout differs from Package.resolved')
    return {'sentryCocoa': cocoa['state']['version'], 'sentryCocoaRevision': revision}


def build_evidence(version):
    lock = (EXAMPLE / 'pubspec.lock').read_text()
    resolved = re.search(r'^  sentry_flutter:\n(?:    [^\n]*\n)*?    version: "([^"]+)"$', lock, re.M)
    if not resolved or resolved[1] != version:
        raise ValueError('Release example resolved a different sentry_flutter version')

    system = platform.system()
    if system == 'Darwin':
        native = cocoa_evidence(EXAMPLE)
    else:
        binary = (EXAMPLE / 'build/windows/x64/runner/Release/sentry.dll' if system == 'Windows'
                  else EXAMPLE / 'build/linux/x64/release/bundle/lib/libsentry.so')
        # Windows 10.6.0 builds from a verified zip, without a git checkout.
        # Query the library actually packaged with the app on both platforms.
        sdk_version = ctypes.CDLL(str(binary.resolve())).sentry_sdk_version
        sdk_version.argtypes = []
        sdk_version.restype = ctypes.c_char_p
        version_info = (EXAMPLE / system.lower() / 'flutter/ephemeral/.plugin_symlinks'
                        / 'sentry_flutter/sentry-native/CMakeCache.txt').read_text()
        expected = re.search(r'^version=(.+)$', version_info, re.M)
        actual = sdk_version().decode('ascii')
        if not expected or actual.split('+')[0] != expected[1]:
            raise ValueError(f'Packaged sentry-native {actual} differs from the Flutter SDK pin')
        native = {'sentryNative': actual,
                  'sentryNativeSha256': hashlib.sha256(binary.read_bytes()).hexdigest()}
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
