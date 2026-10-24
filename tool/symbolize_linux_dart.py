#!/usr/bin/env python3
"""Resolve Linux Dart AOT PCs using exact ELF build IDs and LLVM DWARF data."""
import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess

from elf_build_id import build_id


def validate_stack(raw, identity):
    if not re.search(r'os: linux arch: x64\b', raw):
        raise ValueError('expected a Linux x64 Dart stack')
    found = re.search(r"build_id: '([0-9a-f]+)'", raw)
    if not found or found.group(1) != identity:
        raise ValueError('stack and ELF build IDs differ')
    # virt is already relative to the DSO. Do not subtract the load address again.
    addresses = re.findall(r'^\s*#\d+ abs [0-9a-f]+ virt ([0-9a-f]+)\b', raw, re.MULTILINE)
    if not addresses:
        raise ValueError('no Dart virtual PCs')
    return ['0x' + address for address in addresses]


def symbolize(report, binary, symbols, symbolizer):
    identity = build_id(str(binary))
    if not identity or build_id(str(symbols)) != identity:
        raise ValueError('binary and symbols build IDs differ')
    resolved = []
    for event in report['events']:
        raw = event.get('contexts', {}).get('apptracer', {}).get('dart_stack_trace', '')
        addresses = validate_stack(raw, identity)
        output = subprocess.check_output(
            [symbolizer, '--output-style=JSON', '--obj=' + str(symbols), *addresses], text=True)
        frames = json.loads(output)
        if not any(symbol.get('FileName', '').endswith('/example/lib/main.dart')
                   and symbol.get('Line', 0) > 0
                   for frame in frames for symbol in frame.get('Symbol', [])):
            raise ValueError('no example source line was recovered')
        resolved.append({'event_id': event['event_id'], 'frames': frames})
    if len(resolved) != 3:
        raise ValueError('expected the three Dart smoke events')
    return {'build_id': identity, 'events': resolved,
            'scope': 'local exact-build Dart source lines; not server symbolication'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--report', required=True, type=Path)
    parser.add_argument('--binary', required=True, type=Path)
    parser.add_argument('--symbols', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--symbolizer', default=shutil.which('llvm-symbolizer') or shutil.which('llvm-symbolizer-14'))
    args = parser.parse_args()
    if not args.symbolizer:
        parser.error('install llvm-14 or provide --symbolizer')
    result = symbolize(json.loads(args.report.read_text(encoding='utf-8')),
                       args.binary, args.symbols, args.symbolizer)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'build_id': result['build_id'], 'events': len(result['events']), 'report': str(args.output)}))


if __name__ == '__main__':
    main()
