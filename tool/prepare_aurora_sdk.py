#!/usr/bin/env python3
"""Fetch/verify the pinned Aurora SDK without adding vendor binaries to Git.

This does not install Aurora tooling, execute vendor programs, initialize Tracer
or upload reports/symbols. Python 3.9+; no third-party Python dependencies.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import stat
import struct
import sys
import tempfile
import time
import urllib.request
import zipfile

from elf_build_id import build_id

LOCK_PATH = Path(__file__).parent / 'aurora/sdk.lock.json'
# ELF class, e_machine. armv7hl is inspected but not an initial supported target.
ELF_ABIS = {'aarch64': (2, 183), 'x86_64': (2, 62), 'armv7hl': (1, 40)}


def sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as source:
        for data in iter(lambda: source.read(1024 * 1024), b''):
            digest.update(data)
    return digest.hexdigest()


def verify(root, lock):
    root = Path(root)
    if root.is_symlink() or not root.is_dir():
        raise ValueError('SDK root must be a real directory')
    for name, expected in lock['files'].items():
        path = root / name
        part = root
        for component in PurePosixPath(name).parts:
            part = part / component
            if part.is_symlink():
                raise ValueError('SDK paths must not contain symlinks')
        if not path.is_file() or sha256(path) != expected:
            raise ValueError('SDK checksum mismatch: ' + name)
    libraries = {}
    for arch, (elf_class, machine) in ELF_ABIS.items():
        path = root / 'aurora/lib' / arch / 'libtracernative.so'
        header = path.read_bytes()[:20]
        if (header[:4] != b'\x7fELF' or header[4:6] != bytes([elf_class, 1]) or
                struct.unpack_from('<H', header, 18)[0] != machine):
            raise ValueError('ELF ABI mismatch: ' + arch)
        identifier = build_id(str(path))
        if not identifier:
            raise ValueError('ELF has no build-id: ' + arch)
        libraries[arch] = {'build_id': identifier, 'sha256': sha256(path)}
    return {'sdk_version': lock['version'], 'archive_sha256': lock['archive_sha256'],
            'libraries': libraries, 'runtime_verified': False}


def extract(archive, destination):
    # Reject links and traversal before writing any file, even for a pinned ZIP.
    with zipfile.ZipFile(archive) as source:
        entries = source.infolist()
        for entry in entries:
            name = PurePosixPath(entry.filename)
            mode = entry.external_attr >> 16
            if (name.is_absolute() or '..' in name.parts or '\\' in entry.filename or
                    ':' in entry.filename or stat.S_ISLNK(mode)):
                raise ValueError('unsafe SDK archive path')
        source.extractall(destination)
        for entry in entries:
            if not entry.is_dir() and (entry.external_attr >> 16) & 0o111:
                (destination / entry.filename).chmod(0o755)


def prepare(destination, archive=None, verify_only=False, lock=None):
    lock = lock or json.loads(LOCK_PATH.read_text(encoding='utf-8'))
    destination = Path(destination).absolute()
    if destination.exists() or destination.is_symlink():
        return verify(destination, lock)
    if verify_only:
        raise ValueError('SDK directory does not exist')
    destination.parent.mkdir(parents=True, exist_ok=True)
    # Staging beside destination allows an atomic rename after all checks pass.
    with tempfile.TemporaryDirectory(prefix='.apptracer-sdk-', dir=destination.parent) as temp:
        staging = Path(temp)
        if archive is None:
            archive = staging / 'sdk.zip'
            started = time.monotonic()
            received = 0
            with urllib.request.urlopen(lock['url'], timeout=30) as response:
                with archive.open('wb') as output:
                    while True:
                        if time.monotonic() - started > 180:
                            raise OSError(f'SDK download exceeded 180 seconds after {received} bytes; '
                                          'retry or provide --archive from a verified local download')
                        block = response.read(128 * 1024)
                        if not block:
                            break
                        output.write(block)
                        received += len(block)
                        if received % (4 * 1024 * 1024) == 0:
                            print(f'SDK download: {received} bytes', file=sys.stderr, flush=True)
        archive = Path(archive)
        if sha256(archive) != lock['archive_sha256']:
            raise ValueError('SDK archive checksum mismatch; destination was not changed')
        unpacked = staging / 'unpacked'
        unpacked.mkdir()
        extract(archive, unpacked)
        report = verify(unpacked, lock)
        if destination.exists() or destination.is_symlink():
            raise ValueError('SDK destination appeared during preparation')
        os.rename(unpacked, destination)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--destination', type=Path,
                        default=Path('build/aurora-sdk/0.1.15'))
    parser.add_argument('--archive', type=Path, help='Use a previously downloaded pinned ZIP')
    parser.add_argument('--verify-only', action='store_true')
    args = parser.parse_args()
    try:
        report = prepare(args.destination, args.archive, args.verify_only)
    except (OSError, ValueError, zipfile.BadZipFile) as error:
        parser.exit(1, str(error) + '\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
