#!/usr/bin/env python3
"""Summarize the jobs, step conclusions and compiled SDKs from this Actions run."""
import json
import os
from pathlib import Path

# Reusable workflows add the called job's name after the caller's name.
PLATFORMS = {
    'linux': ('ubuntu-22.04', {'linux': 'Linux release and runtime / ubuntu'}),
    'macos': ('macos-15', {'macos': 'macOS release and lifecycle / macos',
                           'symbols': 'macOS exact-build symbols / symbols'}),
    'windows': ('windows-2022', {'windows': 'Windows release preparation / windows',
                                 'windows-runtime': 'Windows native runtime / native'}),
}


def make_report(needs, jobs):
    version = needs['select']['outputs'].get('version')
    report = {'candidate': version, 'overall': 'passed', 'operatingSystems': {},
              'selection': needs['select']['result']}
    by_name = {job['name']: job for job in jobs}
    for platform, (runner, suites) in PLATFORMS.items():
        platform_jobs = {'precheck': f'Precheck ({runner})', **suites}
        stages = {}
        for key, name in platform_jobs.items():
            result = needs[key]['result']
            evidence = by_name.get(name, {})
            status = evidence.get('conclusion') or ('skipped' if result == 'skipped' else 'unknown')
            stage = {'status': status, 'steps': evidence.get('steps', []),
                     'url': evidence.get('html_url')}
            if key in ('linux', 'macos', 'symbols', 'windows'):
                raw = needs[key]['outputs'].get('versions')
                stage['versions'] = json.loads(raw) if raw else {}
                native_fields = (('sentryCocoa', 'sentryCocoaRevision') if platform == 'macos'
                                 else ('sentryNative', 'sentryNativeSha256'))
                versions = stage['versions']
                if status == 'success' and (versions.get('sentryFlutter') != version or
                        not all(versions.get(k) for k in ('flutter', 'dart', *native_fields))):
                    stage['status'] = 'missing-build-evidence'
            stages[key] = stage
        statuses = {stage['status'] for stage in stages.values()}
        passed = statuses == {'success'} and version and all(
            needs[key]['result'] == 'success' for key in suites)
        if not passed:
            report['overall'] = 'failed'
        report['operatingSystems'][platform] = {'passed': bool(passed), 'stages': stages}
    return report


def main():
    path = Path('jobs.jsonl')
    jobs = [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []
    report = make_report(json.loads(os.environ['NEEDS']), jobs)
    output = Path('build/sentry-candidate/report.json')
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__':
    main()
