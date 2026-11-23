#!/usr/bin/env python3
"""Require external workflow actions to use immutable commits and version comments."""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parent.parent
WORKFLOWS = ROOT / '.github/workflows'
USES = re.compile(r'^(?P<indent>\s*)(?:-\s+)?uses\s*:\s*(?P<value>.*)$')
PIN = re.compile(r'^[^@\s]+@[0-9a-f]{40}$')
BLOCK_SCALARS = {'>', '>-', '>+', '|', '|-', '|+'}


def _uses_value(lines, index, match):
    value, separator, comment = match.group('value').partition('#')
    value = value.strip()
    comment = comment.strip() if separator else ''
    if value in BLOCK_SCALARS:
        indent = len(match.group('indent'))
        continuation = []
        for line in lines[index + 1:]:
            if not line.strip():
                continue
            if len(line) - len(line.lstrip()) <= indent:
                break
            continuation.append(line.strip())
        value = ' '.join(continuation)
    return value.strip('\'"'), comment


def check_workflow(path):
    errors = []
    lines = path.read_text().splitlines()
    for index, line in enumerate(lines):
        match = USES.match(line)
        if not match:
            continue
        value, comment = _uses_value(lines, index, match)
        if value.startswith('./'):
            continue
        location = f'{path}:{index + 1}'
        if not PIN.fullmatch(value):
            errors.append(
                f'{location}: external action must use a full 40-character commit SHA: {value}'
            )
        elif not comment:
            errors.append(f'{location}: commit SHA must have a human-readable version comment')
    return errors


def check_workflows(directory=WORKFLOWS):
    paths = sorted({*directory.rglob('*.yml'), *directory.rglob('*.yaml')})
    errors = [error for path in paths for error in check_workflow(path)]
    return paths, errors


def main():
    paths, errors = check_workflows()
    if errors:
        print('\n'.join(errors), file=sys.stderr)
        return 1
    print(f'Checked external action pins in {len(paths)} workflow files.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
