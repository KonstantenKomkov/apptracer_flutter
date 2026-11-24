#!/usr/bin/env python3
"""Verify a release RPM against its unstripped ELF files and collect Tracer symbols."""
import argparse
import contextlib
import getpass
import hashlib
import json
import os
from pathlib import Path
import re
import runpy
import shutil
import struct
import subprocess
import sys
import tempfile
import uuid


def build_id(path):
    description = subprocess.check_output(['file', '-b', str(path)], text=True)
    match = re.search(r'BuildID\[\w+\]=([a-fA-F0-9]+)', description)
    if not match:
        raise ValueError(f'{path.name}: missing ELF build-id')
    return match[1].lower()


def dump_modules(path):
    data = path.read_bytes()
    if data[:4] != b'MDMP':
        raise ValueError('Expected a Breakpad minidump')
    count, directory = struct.unpack_from('<II', data, 8)
    modules = {}
    for index in range(count):
        kind, size, offset = struct.unpack_from('<III', data, directory + 12 * index)
        if kind != 4:
            continue
        n, = struct.unpack_from('<I', data, offset)
        if size < 4 + 108 * n:
            raise ValueError('Invalid module list')
        for i in range(n):
            record = offset + 4 + i * 108
            name_offset, = struct.unpack_from('<I', data, record + 20)
            length, = struct.unpack_from('<I', data, name_offset)
            name = data[name_offset + 4:name_offset + 4 + length].decode('utf-16-le')
            cv_size, cv = struct.unpack_from('<II', data, record + 76)
            if data[cv:cv + 4] == b'LEpB':
                modules[Path(name).name] = data[cv + 4:cv + cv_size].hex()
    return modules


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('release', type=Path, help='build/aurora/<tools>/<arch>/release')
    parser.add_argument('--sdk', type=Path, required=True, help='prepared Tracer SDK directory')
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--library', type=Path, action='append', default=[],
                        help='additional unstripped ELF packaged in the application lib directory')
    parser.add_argument('--minidump', type=Path, help='optional system dump from the same installed RPM')
    parser.add_argument('--upload', action='store_true')
    args = parser.parse_args()
    release = args.release.resolve()
    vendor = (args.sdk / 'symupload/symupload.py').resolve(strict=True)
    rpms = list((release / 'RPMS').glob('*.rpm'))
    if len(rpms) != 1:
        raise ValueError('Expected one signed application RPM in RPMS')
    rpm = rpms[0]
    members = subprocess.check_output(['bsdtar', '-tf', rpm], text=True).splitlines()
    runners = [name for name in members if re.fullmatch(r'\./usr/bin/[a-zA-Z0-9_.-]+', name)]
    if len(runners) != 1:
        raise ValueError('Expected one application runner')
    runner = Path(runners[0]).name
    plugin = 'libapptracer_flutter_aurora_platform_plugin.so'
    inputs = [release / runner, release / 'plugins/apptracer_flutter_aurora' / plugin, *args.library]
    modules = dump_modules(args.minidump) if args.minidump else None
    digest = hashlib.sha256(rpm.read_bytes()).hexdigest()
    dest = args.out.resolve() / digest
    records = []
    with tempfile.TemporaryDirectory() as temp:
        root = Path(temp)
        (root / 'inputs').mkdir()
        for source in inputs:
            name = source.name
            if not re.fullmatch(r'[A-Za-z0-9_.-]+', name):
                raise ValueError('Unexpected module name')
            member = runners[0] if name == runner else f'./usr/share/{runner}/lib/{name}'
            if member not in members:
                raise ValueError(f'{name}: missing from RPM')
            packaged = root / 'packaged'
            with packaged.open('wb') as output:
                subprocess.run(['bsdtar', '-xOf', rpm, member], stdout=output, check=True)
            identity = build_id(source)
            if build_id(packaged) != identity or (modules is not None and modules.get(name) != identity):
                raise ValueError(f'{name}: build-id mismatch')
            shutil.copy2(source, root / 'inputs' / name)
            records.append({'module': name, 'build_id': identity, 'path': member[1:],
                            'rpm_elf_sha256': hashlib.sha256(packaged.read_bytes()).hexdigest()})
        subprocess.run([sys.executable, vendor, '--no-upload', '--target-platform', 'linux',
                        '-d', 'inputs', '-o', 'symbols'], cwd=root, check=True)
        dest.mkdir(parents=True, exist_ok=True)
        for item in records:
            name = item['module']
            guid = uuid.UUID(bytes_le=bytes.fromhex(item['build_id'][:32])).hex.upper() + '0'
            rel = Path(name, guid, name + '.sym')
            sym = root / 'symbols' / rel
            with sym.open(encoding='utf-8') as file:
                header = file.readline().split()
                if header[3:] != [guid, name] or not any(line.startswith('FILE ') for line in file):
                    raise ValueError(f'{name}: missing matching DWARF source information')
            item['breakpad_id'] = guid
            (dest / rel).parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(sym, dest / rel)
        manifest = {'rpm_sha256': digest, 'modules': records}
        (dest / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
        if args.upload:
            token = os.environ.get('TRACER_AURORA_PLUGIN_TOKEN') or getpass.getpass('Tracer plugin token: ')
            # The vendor CLI includes the token in error URLs. Keep it out of argv and logs.
            try:
                with open(os.devnull, 'w') as quiet, contextlib.redirect_stdout(quiet), contextlib.redirect_stderr(quiet):
                    upload = runpy.run_path(str(vendor))['do_upload']
                    for item in records:
                        upload(str(root / 'symbols' / item['module']), 'https://plugin-api.apptracer.ru',
                               token, False, True)
            except Exception as error:
                raise RuntimeError(f'Tracer symbol upload failed ({type(error).__name__})') from None
    print(dest / 'manifest.json')


if __name__ == '__main__':
    main()
