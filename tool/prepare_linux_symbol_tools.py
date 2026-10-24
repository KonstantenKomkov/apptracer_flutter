#!/usr/bin/env python3
"""Download pinned upstream symbol tools, checking SHA-256 before extraction."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import tarfile
from urllib.request import urlopen

TOOLS = {
    'minidump-stackwalk': (
        'https://github.com/rust-minidump/rust-minidump/releases/download/v0.27.0/'
        'minidump-stackwalk-x86_64-unknown-linux-gnu.tar.xz',
        '0020324c54cc359596e927ee907204f4c8d4da6718765536edcabaa1622122ad'),
    'dump_syms': (
        'https://github.com/mozilla/dump_syms/releases/download/v2.3.9/'
        'dump_syms-x86_64-unknown-linux-gnu.tar.xz',
        '0fc852a86b00337407d9d423cc388a24c3b489ccaaedcf92623cad57af5ca8ad'),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    for name, (url, expected) in TOOLS.items():
        with urlopen(url, timeout=60) as response:
            data = response.read()
        if hashlib.sha256(data).hexdigest() != expected:
            raise ValueError(f'{name}: archive SHA-256 mismatch')
        with tarfile.open(fileobj=io.BytesIO(data), mode='r:xz') as archive:
            matches = [m for m in archive.getmembers()
                       if m.isfile() and Path(m.name).name == name]
            if len(matches) != 1:
                raise ValueError(f'{name}: expected one executable')
            # Copy just the known executable; never extract archive paths/links.
            executable = args.output / name
            executable.write_bytes(archive.extractfile(matches[0]).read())
            executable.chmod(0o755)
    (args.output / 'sources.json').write_text(json.dumps(TOOLS, indent=2) + '\n')


if __name__ == '__main__':
    main()
