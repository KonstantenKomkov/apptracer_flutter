#!/usr/bin/env python3
"""Decode a macOS Dart AOT stack using the exact Mach-O split-debug-info file.

Uses virtual PCs directly with Apple's atos. The original stack is never
rewritten to work around Flutter/native_stack_traces version incompatibilities.
No network requests, credentials or server symbolication are involved.
"""
import argparse
from pathlib import Path
import re
import subprocess
import sys


FRAME = re.compile(r'^\s*#(\d+)\s+abs\s+([0-9a-fA-F]+)\s+virt\s+([0-9a-fA-F]+)(?:\s+.*)?$')


def normalized_id(value):
    value = value.replace('-', '').lower()
    if not re.fullmatch(r'[0-9a-f]{32}', value):
        raise ValueError('expected a Mach-O UUID')
    return value


def macho_uuids(path):
    text = subprocess.check_output(['xcrun', 'dwarfdump', '--uuid', str(path)], text=True)
    records = re.findall(r'^UUID: ([0-9A-Fa-f-]+) \(([^)]+)\)', text, re.MULTILINE)
    result = {arch: normalized_id(value) for value, arch in records}
    if not result or len(result) != len(records):
        raise ValueError('missing or ambiguous Mach-O UUID: ' + str(path))
    return result


def validate_stack(raw, symbol_ids, image_ids):
    header = re.search(r'^os: macos arch: (arm64|x64)\b', raw, re.MULTILINE)
    identity = re.search(r"^build_id: '([0-9a-fA-F]+)'$", raw, re.MULTILINE)
    base = re.search(r'^isolate_dso_base: ([0-9a-fA-F]+),', raw, re.MULTILINE)
    if not header or not identity or not base:
        raise ValueError('missing macOS architecture, build_id or isolate_dso_base')
    arch = {'arm64': 'arm64', 'x64': 'x86_64'}[header[1]]
    build_id = normalized_id(identity[1])
    if symbol_ids.get(arch) != build_id or image_ids.get(arch) != build_id:
        raise ValueError('stack, symbols and App.framework UUID/architecture do not match')
    frames = []
    for line in raw.splitlines():
        if not re.match(r'^\s*#\d+', line):
            continue
        match = FRAME.fullmatch(line)
        if not match:
            raise ValueError('Dart frame has no unambiguous absolute/virtual PC')
        absolute, virtual = int(match[2], 16), int(match[3], 16)
        if absolute - int(base[1], 16) != virtual:
            raise ValueError('virtual PC disagrees with absolute PC and DSO base')
        frames.append({'index': int(match[1]), 'virtual_pc': hex(virtual)})
    if not frames:
        raise ValueError('stack has no Dart AOT frames')
    return arch, build_id, frames


def symbolize(raw, symbols, app_image):
    arch, build_id, frames = validate_stack(raw, macho_uuids(symbols), macho_uuids(app_image))
    output = subprocess.check_output(
        ['xcrun', 'atos', '-arch', arch, '-o', str(symbols),
         *[frame['virtual_pc'] for frame in frames]], text=True)
    lines = output.splitlines()
    if len(lines) != len(frames):
        raise ValueError('atos returned an unexpected number of frames')
    for frame, line in zip(frames, lines):
        frame['symbol'] = line
    if not any(re.search(r'\([^()]+\.dart:\d+\)', line) for line in lines):
        raise ValueError('no Dart source locations recovered')
    return {'architecture': arch, 'build_id': build_id, 'frames': frames}


def decoded_text(result):
    return '\n'.join(f"#{frame['index']:02d} {frame['virtual_pc']} {frame['symbol']}"
                     for frame in result['frames']) + '\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--stack', type=Path, required=True)
    parser.add_argument('--symbols', type=Path, required=True)
    parser.add_argument('--app-image', type=Path, required=True,
                        help='App.framework/App from the exact release .app')
    args = parser.parse_args()
    try:
        result = symbolize(args.stack.read_text(encoding='utf-8'), args.symbols, args.app_image)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(str(error), file=sys.stderr)
        return 1
    print(decoded_text(result), end='')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
