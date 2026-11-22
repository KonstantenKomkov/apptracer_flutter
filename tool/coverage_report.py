#!/usr/bin/env python3
"""Merge package LCOV files and compare critical-file coverage with a baseline."""
import argparse
import html
import json
from pathlib import Path

from package_catalog import packages

ROOT = Path(__file__).resolve().parent.parent
CRITICAL = {
    'parser': 'packages/apptracer_flutter_platform_interface/lib/src/models/dart_stack_trace.dart',
    'tracer_client': 'packages/apptracer_flutter/lib/src/tracer_client.dart',
    'lifecycle': 'packages/apptracer_flutter_platform_interface/lib/src/method_channel_tracer.dart',
    'http_transport': 'packages/apptracer_flutter_http/lib/src/tracer_http_tracer.dart',
}


def generated(path: str) -> bool:
    return path.endswith(('.g.dart', '.freezed.dart', '.mocks.dart')) or path.endswith('/pigeon/tracer_api.dart')


def collect() -> tuple[dict, list[str], list[str]]:
    files = {}
    included = []
    skipped = []
    for row in packages():
        package = row['path']
        if package.endswith('/example') or row['vm'] != 'true':
            skipped.append(package)
            continue
        lcov = ROOT / package / 'coverage/lcov.info'
        if not lcov.is_file() or not lcov.stat().st_size:
            raise SystemExit(f'Missing or empty coverage input: {lcov}')
        included.append(package)
        current = None
        measured = False
        for line in lcov.read_text().splitlines():
            if line.startswith('SF:'):
                source = line[3:]
                if source.startswith(package + '/'):
                    source = source[len(package) + 1:]
                if not source.startswith('lib/') or generated(source):
                    current = None
                else:
                    current = f'{package}/{source}'
                    files.setdefault(current, {})
            elif line.startswith('DA:') and current:
                measured = True
                number, hits = line[3:].split(',')[:2]
                values = files[current]
                values[int(number)] = values.get(int(number), 0) + int(hits)
        if not measured:
            raise SystemExit(f'No production lines in {lcov}')
    return files, included, skipped


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', type=Path, default=ROOT / 'tool/coverage_baseline.json')
    parser.add_argument('--output', type=Path, default=ROOT / 'build/coverage')
    args = parser.parse_args()
    files, included, skipped = collect()
    baseline = json.loads(args.baseline.read_text())
    args.output.mkdir(parents=True, exist_ok=True)

    combined = []
    summary_files = {}
    for path in sorted(files):
        lines = files[path]
        covered = sum(hit > 0 for hit in lines.values())
        total = len(lines)
        summary_files[path] = {'covered': covered, 'total': total}
        combined.append(f'SF:{path}')
        combined.extend(f'DA:{line},{hit}' for line, hit in sorted(lines.items()))
        combined.extend((f'LF:{total}', f'LH:{covered}', 'end_of_record'))
    (args.output / 'lcov.info').write_text('\n'.join(combined) + '\n')

    total = sum(value['total'] for value in summary_files.values())
    covered = sum(value['covered'] for value in summary_files.values())
    critical = {}
    for name, path in CRITICAL.items():
        if path not in summary_files or not summary_files[path]['total']:
            raise SystemExit(f'Missing critical file coverage: {path}')
        current = summary_files[path]
        previous = baseline[path]
        ratio = current['covered'] / current['total'] if current['total'] else 0
        entry = {**current, 'ratio': ratio}
        old_ratio = previous['covered'] / previous['total'] if previous['total'] else 0
        entry['baselineRatio'] = old_ratio
        entry['deltaPercentagePoints'] = (ratio - old_ratio) * 100
        critical[name] = entry
    result = {
        'packages': included,
        'skipped': skipped,
        'overall': {'covered': covered, 'total': total,
                    'ratio': covered / total if total else 0},
        'files': summary_files,
        'critical': critical,
        'unmeasuredLibraryFiles': sorted(
            path.relative_to(ROOT).as_posix()
            for package in included for path in (ROOT / package / 'lib').rglob('*.dart')
            if path.relative_to(ROOT).as_posix() not in files and not generated(path.as_posix())
        ),
        'note': 'VM unit-test coverage of LCOV-reported lines. Chrome tests run separately.',
    }
    (args.output / 'summary.json').write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')

    rows = []
    for name, entry in critical.items():
        delta = entry.get('deltaPercentagePoints')
        rows.append('<tr><td>{}</td><td>{}/{}</td><td>{:.2f}%</td><td>{}</td></tr>'.format(
            html.escape(name), entry['covered'], entry['total'], entry['ratio'] * 100,
            '' if delta is None else f'{delta:+.2f} pp'))
    page = '''<!doctype html><meta charset="utf-8"><title>AppTracer coverage</title>
<style>body{{font-family:sans-serif}}td,th{{padding:.35em 1em;text-align:left}}table{{border-collapse:collapse}}td{{border-bottom:1px solid #ddd}}</style>
<h1>Dart unit-test coverage</h1><p>Overall: {}/{} ({:.2f}%). Not evidence of live delivery.</p>
<table><tr><th>Critical file</th><th>Lines</th><th>Coverage</th><th>Baseline delta</th></tr>{}</table>
<p>VM line coverage excludes examples, generated sources and Chrome-only code.
See <a href="summary.json">file breakdown and omissions</a> or <a href="lcov.info">LCOV</a>.</p>'''.format(
        covered, total, (covered / total * 100 if total else 0), ''.join(rows))
    (args.output / 'index.html').write_text(page)
    print(json.dumps({'overall': result['overall'], 'critical': critical}, indent=2))


if __name__ == '__main__':
    main()
