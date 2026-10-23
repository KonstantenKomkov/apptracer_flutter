#!/usr/bin/env python3
"""Inspect pinned Aurora ELF dependencies/exports without loading vendor code."""
import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess

from prepare_aurora_sdk import ELF_ABIS, LOCK_PATH, verify

REQUIRED = {'tracer_init', 'tracer_set_platform_info2', 'tracer_set_key',
            'tracer_set_userid', 'tracer_log', 'tracer_upload',
            'tracer_disable_upload', 'tracer_aurora_collect_minidump_from_cachedir'}


def inspect(root):
    verify(root, json.loads(LOCK_PATH.read_text(encoding='utf-8')))
    readelf = shutil.which('readelf')
    if readelf:
        commands = [[readelf, '--wide', '--dynamic', '--version-info'],
                    [readelf, '--wide', '--dyn-syms']]
    else:
        objdump = shutil.which('llvm-objdump')
        if not objdump:
            objdump = subprocess.check_output(['xcrun', '--find', 'llvm-objdump'], text=True).strip()
        commands = [[objdump, '-p'], [objdump, '-T']]
    result = {}
    for arch in ELF_ABIS:
        library = root / 'aurora/lib' / arch / 'libtracernative.so'
        metadata, symbols = [subprocess.check_output([*command, str(library)], text=True)
                             for command in commands]
        exports = set()
        for line in symbols.splitlines():
            columns = line.split()
            if columns and 'UND' not in columns and '*UND*' not in columns:
                name = columns[-1].split('@', 1)[0]
                if name.startswith('tracer_'):
                    exports.add(name)
        missing = sorted(REQUIRED - exports)
        if missing:
            raise ValueError(f'{arch} is missing required native exports: {missing}')
        needed = re.findall(r'\(NEEDED\).*?\[(.*?)\]', metadata) if readelf else re.findall(r'^\s*NEEDED\s+(\S+)', metadata, re.M)
        versions = set(re.findall(r'\b(?:GLIBC_[0-9.]+|OPENSSL_[0-9_]+)\b', metadata))
        result[arch] = {'needed': sorted(needed), 'symbol_versions': sorted(versions),
                        'tracer_exports': sorted(exports), 'runtime_verified': False}
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sdk', type=Path, default=Path('build/aurora-sdk/0.1.15'))
    args = parser.parse_args()
    print(json.dumps(inspect(args.sdk), indent=2))


if __name__ == '__main__':
    main()
