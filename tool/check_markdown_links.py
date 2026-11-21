#!/usr/bin/env python3
"""Check local Markdown files and GitHub-style anchors without external services."""
import argparse
from pathlib import Path
import re
import unicodedata
from urllib.parse import unquote

LINK = re.compile(r'!?(?:\[[^\]]*\])\(([^)]+)\)')
HEADING = re.compile(r'^#{1,6}\s+(.+?)\s*$')


def slug(text: str) -> str:
    text = re.sub(r'\s*\{#[^}]+\}\s*$', '', text.strip()).lower()
    result = []
    for char in text:
        if char.isspace():
            result.append('-')
        elif char.isalnum() or char in {'_', '-'}:
            result.append(char)
        elif unicodedata.category(char).startswith('M'):
            result.append(char)
    return ''.join(result)


def anchors(path: Path) -> set[str]:
    result = set()
    counts = {}
    for line in path.read_text(encoding='utf-8').splitlines():
        for html_anchor in re.finditer(r'(?:id|name)=["\']([^"\']+)["\']', line):
            result.add(html_anchor.group(1))
        match = HEADING.match(line)
        if not match:
            continue
        base = slug(match.group(1))
        count = counts.get(base, 0)
        counts[base] = count + 1
        result.add(base if count == 0 else f'{base}-{count}')
        explicit = re.search(r'\{#([^}]+)\}\s*$', match.group(1))
        if explicit:
            result.add(explicit.group(1))
    return result


def check(root: Path, files: list[Path]) -> list[str]:
    cache = {}
    errors = []
    for source in files:
        for line_number, line in enumerate(source.read_text(encoding='utf-8').splitlines(), 1):
            for match in LINK.finditer(line):
                target = match.group(1).strip()
                if target.startswith('<') and target.endswith('>'):
                    target = target[1:-1]
                if not target or target.startswith(('http://', 'https://', 'mailto:', 'data:')):
                    continue
                target = target.split(' "', 1)[0].split(" '", 1)[0]
                path_part, _, fragment = target.partition('#')
                resolved = (source.parent / unquote(path_part)).resolve() if path_part else source.resolve()
                if root not in resolved.parents and resolved != root:
                    errors.append(f'{source.relative_to(root)}:{line_number}: link escapes repository: {target}')
                    continue
                if not resolved.exists():
                    errors.append(f'{source.relative_to(root)}:{line_number}: missing target: {target}')
                    continue
                if fragment and resolved.suffix.lower() in {'.md', '.markdown', '.mdown', '.mkd'}:
                    if resolved not in cache:
                        cache[resolved] = anchors(resolved)
                    if unquote(fragment) not in cache[resolved]:
                        errors.append(f'{source.relative_to(root)}:{line_number}: missing anchor: {target}')
    return errors


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('paths', nargs='*', type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    files = args.paths or sorted(root.glob('**/*.md'))
    files = [path if path.is_absolute() else (root / path).resolve() for path in files]
    files = [path for path in files if '.git' not in path.parts and 'build' not in path.parts]
    errors = check(root, files)
    if errors:
        print('\n'.join(errors))
        raise SystemExit(f'{len(errors)} broken Markdown link(s)')
    print(f'Checked {len(files)} Markdown files: all local links and anchors valid')


if __name__ == '__main__':
    main()
