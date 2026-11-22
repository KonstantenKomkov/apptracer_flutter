#!/usr/bin/env python3
"""Update the pinned CI Flutter baseline from the official stable release metadata."""
import argparse
import json
from pathlib import Path
import urllib.request


def latest_stable() -> str:
    url = 'https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json'
    with urllib.request.urlopen(url, timeout=30) as response:
        metadata = json.load(response)
    stable_hash = metadata['current_release']['stable']
    release = next(item for item in metadata['releases'] if item['hash'] == stable_hash)
    return release['version']


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='Report without modifying the pin')
    args = parser.parse_args()
    path = Path(__file__).resolve().parent.parent / '.github/flutter-version'
    current = path.read_text().strip()
    latest = latest_stable()
    print(json.dumps({'current': current, 'latestStable': latest, 'updateAvailable': current != latest}))
    if not args.check and current != latest:
        path.write_text(latest + '\n')


if __name__ == '__main__':
    main()
