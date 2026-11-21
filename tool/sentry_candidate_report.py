#!/usr/bin/env python3
"""Create a machine-readable Sentry candidate summary without exposing credentials."""
import argparse
import json
from pathlib import Path

SCENARIOS = [
    'resolver_analyze_unit', 'release_build', 'deferred_bootstrap', 'offline_retry',
    'inflight_cancellation', 'stop_clear_revoke', 'account_isolation', 'native_crash',
    'no_replay_after_revoke', 'dart_native_source_maps', 'native_handler_packaging',
    'missing_mismatched_symbols',
]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--lock', type=Path, required=True)
    parser.add_argument('--precheck', required=True)
    parser.add_argument('--linux', required=True)
    parser.add_argument('--macos', required=True)
    parser.add_argument('--windows', required=True)
    parser.add_argument('--symbols', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    version = None
    in_sentry = False
    lines = args.lock.read_text().splitlines() if args.lock.exists() else []
    for line in lines:
        if line == '  sentry_flutter:':
            in_sentry = True
        elif in_sentry and line.strip().startswith('version:'):
            version = line.strip().split('"')[1]
            break
    if version is None:
        version = 'unresolved'

    statuses = {'precheck': args.precheck, 'linux': args.linux,
                'macos': args.macos, 'windows': args.windows, 'symbols': args.symbols}
    report = {'candidate': version, 'overall': 'passed', 'operatingSystems': {}}
    for os_name in ['linux', 'macos', 'windows']:
        blocked = statuses['precheck'] != 'success' or statuses[os_name] != 'success'
        state = ('blocked' if statuses['precheck'] != 'success'
                 else 'failed' if blocked else 'passed')
        report['operatingSystems'][os_name] = {
            'status': state,
            'stages': {name: ('blocked' if state == 'blocked' else state) for name in SCENARIOS},
        }
        if state != 'passed':
            report['overall'] = 'failed'
    report['symbolChecks'] = {
        'status': 'passed' if statuses['symbols'] == 'success' else 'failed',
        'workflowStatus': statuses['symbols'],
    }
    if statuses['symbols'] != 'success':
        report['overall'] = 'failed'
    report['notes'] = [
        'No production pin was changed and no package was published.',
        'A pin-changing PR still requires hosted consumer and live Tracer evidence.',
    ]
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + '\n')
    print(json.dumps({'candidate': version, 'overall': report['overall']}))


if __name__ == '__main__':
    main()
