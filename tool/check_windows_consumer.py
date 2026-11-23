#!/usr/bin/env python3
"""Build, publish-dry-run and exercise an isolated Windows consumer; never publishes."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile

from check_linux_consumer import MAIN, runtime
from consumer_packages import (PUB_DEV, SIBLINGS, check_candidates, check_consumer_graph,
                               consumer_dependencies, consumer_scope, is_sdk_pin_warning, write_overrides)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--candidate-facade', action='store_true')
    parser.add_argument('--hosted-desktop', help='Exact published desktop version (default: 2.0.0)')
    parser.add_argument('--facade-version', help='Exact hosted facade version (defaults to the matching release)')
    parser.add_argument('--bundle', type=Path, help='Only run a previously built consumer bundle')
    parser.add_argument('--dump-syms', required=True, type=Path)
    parser.add_argument('--native-source', type=Path)
    args = parser.parse_args()
    if os.name != 'nt':
        parser.error('Run on Windows x64')
    if args.candidate_facade and args.hosted_desktop:
        parser.error('A hosted desktop check must use a hosted facade')
    for version in [args.facade_version, args.hosted_desktop]:
        if version and not re.fullmatch(r'\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?', version):
            parser.error('Expected an exact package version')
    args.facade_version = args.facade_version or ('1.4.0' if args.hosted_desktop == '1.0.1' else '1.5.0')
    stable_flutter_error = args.candidate_facade or tuple(map(int, args.facade_version.split('-')[0].split('.'))) >= (0, 2, 2)
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    report = {'success': False, 'published': False,
              'scope': 'Previously built bundle; runtime only' if args.bundle else consumer_scope(args.candidate_facade)}
    repo = Path(__file__).resolve().parent.parent
    env = {k: v for k, v in os.environ.items() if not k.startswith('TRACER_')}
    env['PUB_HOSTED_URL'] = PUB_DEV
    env['SENTRY_NATIVE_BACKEND'] = 'native'
    env['GIT_CONFIG_COUNT'] = '1'
    env['GIT_CONFIG_KEY_0'] = 'core.longpaths'
    env['GIT_CONFIG_VALUE_0'] = 'true'
    counter = 0

    def run(command, cwd, sdk_warning=False):
        nonlocal counter
        counter += 1
        log = output / f'{counter:02d}-{Path(command[0]).name}.log'
        print('Running: ' + ' '.join(map(str, command)), flush=True)
        if command[0] in ('flutter', 'dart'):
            command[0] = shutil.which(command[0] + '.bat') or command[0]
        with log.open('w', encoding='utf-8') as stream:
            result = subprocess.run(command, cwd=cwd, env=env, stdout=stream,
                                    stderr=subprocess.STDOUT, timeout=1200)
        content = log.read_text(encoding='utf-8', errors='replace')
        if sdk_warning and is_sdk_pin_warning(result.returncode, content):
            report['publish_warning'] = 'Intentional exact sentry_flutter 10.6.0 pin'
        elif result.returncode:
            raise RuntimeError(f'Command failed ({result.returncode}); see {log}')
        return content

    try:
        if args.bundle:
            report['runtime'] = runtime(args.bundle.resolve(), output, stable_flutter_error, windows=True)
        else:
            report['revision'] = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repo, text=True).strip()
            report['source_dirty'] = bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=repo))
            with tempfile.TemporaryDirectory(prefix='apptracer-consumer-') as directory:
                root = Path(directory)
                if args.candidate_facade:
                    check_candidates(repo, root, output, run, report)
                else:
                    report['hosted_desktop_version'] = args.hosted_desktop or '2.0.0'
                deps = consumer_dependencies(args.candidate_facade, facade=args.facade_version,
                                             desktop=args.hosted_desktop or '2.0.0')
                app = root / 'consumer'
                run(['flutter', 'create', '--platforms=windows', '--no-pub', '--project-name',
                     'tracer_external_consumer', str(app)], root)
                (app / 'pubspec.yaml').write_text('name: tracer_external_consumer\npublish_to: none\n'
                    'version: 1.0.0+1\nenvironment:\n  sdk: ^3.5.0\ndependencies:\n'
                    '  flutter:\n    sdk: flutter\n' + deps +
                    'flutter:\n  uses-material-design: true\n', encoding='utf-8')
                if args.candidate_facade:
                    write_overrides(app, SIBLINGS)
                (app / 'lib/main.dart').write_text(MAIN.replace('Ubuntu', 'Windows').replace("stdout.writeln('CONSUMER_OK');", "await File(Platform.environment['TRACER_CONSUMER_DONE']!).writeAsString('CONSUMER_OK');"), encoding='utf-8')
                shutil.rmtree(app / 'test')
                (app / 'analysis_options.yaml').write_text('analyzer:\n  errors:\n    unused_import: error\n', encoding='utf-8')
                cmake = app / 'windows/CMakeLists.txt'
                content = cmake.read_text(encoding='utf-8')
                if args.native_source:
                    source_path = args.native_source.resolve().as_posix()
                    # 10.x downloads a zip before FetchContent sees overrides.
                    env['SENTRY_NATIVE_FETCH_METHOD'] = 'git'
                    content = content.replace('include(flutter/generated_plugins.cmake)',
                        'set(FETCHCONTENT_SOURCE_DIR_SN "' + source_path + '" CACHE PATH "Pinned local SDK" FORCE)\n'
                        'set(FETCHCONTENT_SOURCE_DIR_SENTRY-NATIVE "' + source_path + '" CACHE PATH "Pinned local SDK" FORCE)\n'
                        'include(flutter/generated_plugins.cmake)')
                cmake.write_text(content, encoding='utf-8')
                run(['flutter', 'pub', 'get'], app)
                graph = json.loads(run(['dart', 'pub', 'deps', '--json'], app))
                check_consumer_graph(graph, root, app, args.candidate_facade, report)
                shutil.copy2(app / 'pubspec.lock', output / 'consumer.pubspec.lock')
                run(['flutter', 'analyze', '--no-pub', '--fatal-infos'], app)
                run(['flutter', 'build', 'windows', '--no-pub', '--release', '--obfuscate',
                     '--split-debug-info=build/symbols'], app)
                bundle = app / 'build/windows/x64/runner/Release'
                assert (bundle / 'sentry-crash.exe').is_file()
                for name in ['msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll']:
                    assert (bundle / name).is_file(), name
                run([sys.executable, str(repo / 'tool/prepare_linux_dart_runtime_symbols.py'), '--windows',
                     '--bundle', str(bundle), '--symbols', str(app / 'build/symbols/app.windows-x64.symbols'),
                     '--dump-syms', str(args.dump_syms.resolve())], root)
                # MSVC writes the runner PDB next to the EXE by default. Keep
                # full debug information in the private symbols artifact only.
                native_symbols = app / 'build/symbols/native'
                native_symbols.mkdir(parents=True, exist_ok=True)
                for pdb in bundle.glob('*.pdb'):
                    shutil.move(str(pdb), native_symbols / pdb.name)
                archive = output / 'consumer-bundle.tar.gz'
                with tarfile.open(archive, 'w:gz') as tar:
                    tar.add(bundle, arcname='bundle')
                report['bundle_sha256'] = hashlib.sha256(archive.read_bytes()).hexdigest()
                shutil.copytree(app / 'build/symbols', output / 'symbols', dirs_exist_ok=True)
                report['runtime'] = runtime(bundle, output, stable_flutter_error, windows=True)
        report['success'] = True
    except Exception as error:
        report['error'] = str(error)
        raise
    finally:
        (output / 'report.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
