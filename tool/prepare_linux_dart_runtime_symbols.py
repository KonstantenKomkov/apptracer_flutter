#!/usr/bin/env python3
"""Create an optional client-side Dart source map from exact-build DWARF.

The compact map exposes function names and source paths, but contains no source
text or full DWARF. Shipping it weakens obfuscation; keep it out when that matters.
"""
import argparse
import gzip
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import uuid

from elf_build_id import build_id


def parse_breakpad(text, identity):
    rows = text.splitlines()
    expected = uuid.UUID(bytes_le=bytes.fromhex(identity)[:16].ljust(16, b'\0')).hex.upper() + '0'
    if not rows or rows[0].split() != ['MODULE', 'Linux', 'x86_64', expected, 'libapp.so']:
        raise ValueError('Dart map module ID does not match the ELF')
    files, functions, lines = {}, [], []
    in_function = False
    for row in rows[1:]:
        if row.startswith('FILE '):
            _, number, path = row.split(' ', 2)
            files[int(number)] = path
            in_function = False
        elif row.startswith('FUNC '):
            fields = row.split(' ', 1)[1]
            if fields.startswith('m '):
                fields = fields[2:]
            address, size, _, name = fields.split(' ', 3)
            functions.append([int(address, 16), int(size, 16), name])
            in_function = True
        elif in_function and row and row[0] in '0123456789abcdefABCDEF':
            address, size, line, file = row.split()
            if int(size, 16) and int(line) > 0:
                lines.append([int(address, 16), int(size, 16), int(file), int(line)])
        elif row and not row.startswith('INLINE'):
            in_function = False
    if not files or not functions or not lines:
        raise ValueError('Dart DWARF must contain functions and source lines')
    ordered = sorted(files)
    indices = {number: index for index, number in enumerate(ordered)}
    for line in lines:
        line[2] = indices[line[2]]
    return {'schema': 1, 'build_id': identity, 'arch': 'x64',
            'files': [files[number] for number in ordered],
            'functions': sorted(functions), 'lines': sorted(lines)}


def prepare(bundle, symbols, dump_syms, windows=False):
    identity = build_id(str(bundle / ('data/app.so' if windows else 'lib/libapp.so')))
    if not identity or identity != build_id(str(symbols)):
        raise ValueError('Dart binary and split-debug-info build IDs differ')
    with tempfile.TemporaryDirectory(prefix='apptracer-dart-map-') as temp:
        stage = Path(temp)
        shutil.copy2(symbols, stage / 'libapp.so')
        subprocess.run([str(dump_syms), '--store', str(stage / 'store'),
                        str(stage / 'libapp.so')], check=True)
        maps = list((stage / 'store').glob('libapp.so/*/libapp.so.sym'))
        if len(maps) != 1:
            raise ValueError('expected one exact-build Dart map')
        data = parse_breakpad(maps[0].read_text(encoding='utf-8'), identity)
    directory = bundle / ('data/apptracer-dart-symbols' if windows else 'lib/apptracer-dart-symbols')
    directory.mkdir(parents=True, exist_ok=True)
    packed = gzip.compress(json.dumps(data, separators=(',', ':')).encode(), mtime=0)
    output = directory / f'{identity}.json.gz'
    output.write_bytes(packed)
    return {'build_id': identity, 'files': len(data['files']),
            'functions': len(data['functions']), 'lines': len(data['lines']),
            'bytes': len(packed), 'output': str(output)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bundle', required=True, type=Path)
    parser.add_argument('--symbols', required=True, type=Path)
    parser.add_argument('--dump-syms', required=True, type=Path)
    parser.add_argument('--windows', action='store_true', help='use Windows Flutter ELF bundle paths')
    args = parser.parse_args()
    print(json.dumps(prepare(args.bundle.resolve(), args.symbols.resolve(), args.dump_syms.resolve(), windows=args.windows)))


if __name__ == '__main__':
    main()
