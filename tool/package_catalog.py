#!/usr/bin/env python3
"""Read the single package catalog for local checks and GitHub Actions."""
import argparse
import csv
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def packages() -> list[dict]:
    with (ROOT / 'tool/packages.tsv').open(newline='') as source:
        return list(csv.DictReader(source, delimiter='\t'))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=['paths', 'publish', 'matrix', 'chrome'])
    args = parser.parse_args()
    rows = packages()
    if args.mode == 'paths':
        print('\n'.join(row['path'] for row in rows))
    elif args.mode == 'publish':
        print('\n'.join(row['path'] for row in rows if row['publishable'] == 'true'))
    elif args.mode == 'matrix':
        names = [Path(row['path']).name for row in rows
                 if not row['path'].endswith('/example')]
        print(json.dumps(names, separators=(',', ':')))
    else:
        print('\n'.join(row['path'] for row in rows if row['chrome'] == 'true'))


if __name__ == '__main__':
    main()
