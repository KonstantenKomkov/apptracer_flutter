#!/usr/bin/env python3
"""Read the package catalog for local checks and GitHub Actions."""
import argparse
import csv
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def packages() -> list[dict]:
    with (ROOT / 'tool/packages.tsv').open(newline='') as source:
        rows = list(csv.DictReader(source, delimiter='\t'))
    paths = [row['path'] for row in rows]
    expected = {p.parent.relative_to(ROOT).as_posix() for pattern in
                ('packages/*/pubspec.yaml', 'packages/*/example/pubspec.yaml')
                for p in ROOT.glob(pattern)}
    if not rows or len(set(paths)) != len(paths) or set(paths) != expected:
        raise ValueError(f'Duplicate or missing catalog entries: {set(paths) ^ expected}')
    for row in rows:
        if row['vm'] not in ('true', 'false') or row['publishable'] not in ('true', 'false'):
            raise ValueError(f'Invalid boolean in catalog: {row}')
        if row['chrome'] not in ('all', '-'):
            if not row['chrome'] or not all((ROOT / row['path'] / f).is_file()
                                            for f in row['chrome'].split()):
                raise ValueError(f'Invalid Chrome test paths: {row}')
    return rows


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=['paths', 'publish', 'matrix', 'minimum'])
    mode = parser.parse_args().mode
    rows = packages()
    if mode in ('paths', 'publish'):
        for row in rows:
            if mode == 'paths' or row['publishable'] == 'true':
                print(row['path'])
    else:
        matrix = [{'package': Path(row['path']).name, 'chrome': row['chrome'] != '-',
                   'vm': row['vm'] == 'true'}
                  for row in rows if not row['path'].endswith('/example')
                  and (mode != 'minimum' or row['native'] != 'desktop')]
        print(json.dumps(matrix, separators=(',', ':')))


if __name__ == '__main__':
    main()
