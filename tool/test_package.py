#!/usr/bin/env python3
"""Run the VM and/or Chrome suites declared for one package."""
import argparse
import subprocess

from package_catalog import ROOT, packages


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('package')
    parser.add_argument('--coverage', action='store_true')
    args = parser.parse_args()
    row = next(row for row in packages() if row['path'] == args.package)
    directory = ROOT / args.package
    command = ['flutter', 'test', '--no-pub', '--reporter=expanded']
    if row['vm'] == 'true':
        options = ['--coverage'] if args.coverage and directory.name != 'example' else []
        subprocess.run(command + options, cwd=directory, check=True)
    if row['chrome'] != '-':
        targets = [] if row['chrome'] == 'all' else row['chrome'].split()
        subprocess.run(command + ['--platform', 'chrome'] + targets, cwd=directory, check=True)


if __name__ == '__main__':
    main()
