#!/usr/bin/env python3
"""Validate an exact-build Linux probe minidump and recover its source frame."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess

from check_linux_runtime import inspect_linux_dump


def crash_frame(report, runner_name):
    crash = report['crash_info']
    if not crash.get('type', '').startswith('SIGSEGV'):
        raise ValueError('not the expected native signal')
    index = crash.get('crashing_thread')
    threads = report.get('threads', [])
    if not isinstance(index, int) or not 0 <= index < len(threads):
        raise ValueError('missing crashing thread')
    for frame in threads[index].get('frames', []):
        if (frame.get('module') == runner_name
                and frame.get('function') == 'apptracer_native_crash()'
                and (frame.get('file') or '').endswith('/linux/runner/my_application.cc')
                and (frame.get('line') or 0) > 0
                and frame.get('trust') in ('context', 'cfi', 'frame_pointer')):
            return frame
    raise ValueError('no trustworthy native probe source frame in the crashing thread')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dump', required=True, type=Path)
    parser.add_argument('--runner', required=True, type=Path)
    parser.add_argument('--symbols', required=True, type=Path,
                        help='Breakpad symbol store generated from exact-build ELF files')
    parser.add_argument('--stackwalk', default=shutil.which('minidump-stackwalk'))
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    if not args.stackwalk:
        parser.error('provide minidump-stackwalk 0.27.0 via --stackwalk or PATH')
    identity = inspect_linux_dump(args.dump.read_bytes(), args.runner)
    report = json.loads(subprocess.check_output(
        [args.stackwalk, '--json', str(args.dump), str(args.symbols)], text=True))
    frame = crash_frame(report, args.runner.name)
    result = {'dump': identity, 'frame': frame, 'stack': report,
              'scope': 'local exact-build native source line; not Tracer symbolication'}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'build_id': identity['runner']['build_id'],
                      'function': frame['function'], 'file': frame['file'], 'line': frame['line']}))


if __name__ == '__main__':
    main()
