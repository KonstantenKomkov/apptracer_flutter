#!/usr/bin/env python3
"""Run one explicitly requested phase of the Aurora sandbox acceptance fixture."""
import argparse
import getpass
import os
import subprocess
import sys

APP = 'ru.apptracer.apptracer_flutter_aurora_example'
DIRECTORY = '"$HOME/.local/share/ru.apptracer/apptracer_flutter_aurora_example"'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('phase', choices=('arm', 'upload'))
    parser.add_argument('ssh_arguments', nargs=argparse.REMAINDER,
                        help='-- followed by SSH options and user@emulator')
    args = parser.parse_args()
    ssh_args = args.ssh_arguments
    if ssh_args[:1] == ['--']:
        ssh_args = ssh_args[1:]
    if not ssh_args:
        parser.error('Provide the SSH destination')
    ssh = ['ssh', '-o', 'BatchMode=yes', *ssh_args]
    token = os.environ.get('TRACER_AURORA_APP_TOKEN') or getpass.getpass('Tracer app token: ')
    if not token or '\n' in token or '\r' in token:
        parser.error('Expected a single nonempty app token')

    # mkdir is the lock for this fixture on the guest. A failed/aborted run
    # must never leave the next launch with an armed command or credentials.
    setup = (
        f'set -eu; umask 077; dir={DIRECTORY}; mkdir -p "$dir"; '
        'mkdir "$dir/acceptance-lock" || exit 2; '
        'trap \'rm -f "$dir/acceptance-lock/input"; rmdir "$dir/acceptance-lock"\' EXIT; '
        'test ! -e "$dir/explicit-test-input"; '
        'cat > "$dir/acceptance-lock/input"; '
        'mv "$dir/acceptance-lock/input" "$dir/explicit-test-input"; '
        'trap \'rm -f "$dir/explicit-test-input" "$dir/acceptance-lock/input"; '
        'rmdir "$dir/acceptance-lock"\' EXIT; '
        f'runtime-manager-tool Control startDebug {APP} --output-to-console'
    )
    process = subprocess.Popen(ssh + [setup], stdin=subprocess.PIPE,
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    try:
        output, _ = process.communicate(f'{args.phase}\n{token}\n'.encode(), timeout=90)
    except subprocess.TimeoutExpired as exc:
        output = exc.output or b''
        subprocess.run(ssh + ['runtime-manager-tool Control terminate ' + APP],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10)
        process.kill()
        process.communicate()
    except KeyboardInterrupt:
        process.kill()
        process.communicate()
        raise
    expected = f'Acceptance {args.phase}, worker exit 0'.encode()
    if expected not in output:
        print('No successful worker receipt. Check the emulator permission dialog.', file=sys.stderr)
        return 1
    print(f'{args.phase}: worker completed. Confirm the report in Tracer after upload.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
