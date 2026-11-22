#!/usr/bin/env python3
"""Run the VM and/or Chrome suites declared for one package."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys

from package_catalog import ROOT, packages


def chrome_executable() -> str:
    if 'CHROME_EXECUTABLE' in os.environ:
        candidates = [os.environ['CHROME_EXECUTABLE']]
    elif sys.platform == 'darwin':
        candidates = ['/Applications/Google Chrome.app/Contents/MacOS/Google Chrome']
    elif sys.platform == 'win32':
        candidates = [str(Path(os.environ[key]) / 'Google/Chrome/Application/chrome.exe')
                      for key in ('LOCALAPPDATA', 'PROGRAMFILES', 'PROGRAMFILES(X86)')
                      if key in os.environ]
    else:
        candidates = ['google-chrome', 'chromium', 'chromium-browser']
    for candidate in candidates:
        executable = shutil.which(candidate)
        if executable:
            return executable
    raise SystemExit('Chrome executable missing. Install Chrome or set CHROME_EXECUTABLE.')


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
        env = {**os.environ, 'CHROME_EXECUTABLE': chrome_executable()}
        subprocess.run(command + ['--platform', 'chrome'] + targets, cwd=directory,
                       env=env, check=True)


if __name__ == '__main__':
    main()
