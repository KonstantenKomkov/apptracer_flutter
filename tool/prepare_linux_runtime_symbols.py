#!/usr/bin/env python3
"""Bundle exact-build native Breakpad maps for the Linux crash daemon."""
import argparse
import json
from pathlib import Path
import subprocess
import uuid

from elf_build_id import build_id


def prepare(bundle, dump_syms, executable='apptracer_desktop_example'):
    if Path(executable).name != executable:
        raise ValueError('--executable must be the runner basename')
    runner = bundle / executable
    store = bundle / 'lib/symbols'
    store.mkdir(parents=True, exist_ok=True)
    result = []
    # Dart AOT split-debug-info is a separate artifact. Do not ship its private
    # deobfuscation map as part of native runner symbolication.
    binaries = [runner, *(p for p in (bundle / 'lib').glob('*.so') if p.name != 'libapp.so')]
    for binary in binaries:
        identity = build_id(str(binary))
        if not identity:
            raise ValueError(f'missing ELF build-id: {binary.name}')
        debug_id = uuid.UUID(bytes_le=bytes.fromhex(identity)[:16].ljust(16, b'\0')).hex.upper() + '0'
        subprocess.run([str(dump_syms), '--store', str(store), str(binary)], check=True)
        symbol = store / binary.name / debug_id / (binary.name + '.sym')
        lines = symbol.read_text(encoding='utf-8').splitlines()
        if lines[0].split() != ['MODULE', 'Linux', 'x86_64', debug_id, binary.name]:
            raise ValueError('symbol module does not match its ELF')
        sources = sum(line.startswith('FILE ') for line in lines)
        functions = sum(line.startswith('FUNC ') for line in lines)
        if not sources or not functions:
            if binary == runner:
                raise ValueError('runner must retain DWARF source lines')
            # Only this invocation's verified output is removed; no tree deletion.
            symbol.unlink()
            continue
        result.append({'module': binary.name, 'build_id': identity, 'debug_id': debug_id,
                       'files': sources, 'functions': functions})
    (store / 'manifest.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bundle', required=True, type=Path)
    parser.add_argument('--dump-syms', required=True, type=Path)
    parser.add_argument('--executable', default='apptracer_desktop_example',
                        help='runner filename in the bundle root')
    args = parser.parse_args()
    print(json.dumps(prepare(args.bundle.resolve(), args.dump_syms.resolve(), args.executable)))


if __name__ == '__main__':
    main()
