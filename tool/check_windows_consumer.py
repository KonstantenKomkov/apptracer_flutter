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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--candidate-facade', action='store_true')
    parser.add_argument('--hosted-desktop', help='Use this published desktop version instead of a source export')
    parser.add_argument('--facade-version', default='1.0.0', help='Exact hosted facade version (default: 1.0.0)')
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
    stable_flutter_error = args.candidate_facade or tuple(map(int, args.facade_version.split('-')[0].split('.'))) >= (0, 2, 2)
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    report = {'success': False, 'published': False}
    repo = Path(__file__).resolve().parent.parent
    env = {k: v for k, v in os.environ.items() if not k.startswith('TRACER_')}
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
        validation = content.split('Validating package...')[-1]
        expected = (sdk_warning and result.returncode == 65
                    and validation.count('\n* ') == 1
                    and 'Your dependency on "sentry_flutter" should allow more than one version.' in validation
                    and 'Package has 1 warning.' in validation and 'error' not in validation.lower())
        if expected:
            report['publish_warning'] = 'Intentional exact sentry_flutter 9.30.1 pin'
        elif result.returncode:
            raise RuntimeError(f'Command failed ({result.returncode}); see {log}')
        return content

    def export(name, root):
        package = Path('packages') / name
        files = subprocess.check_output(['git', 'ls-files', '-z', '--cached', '--others',
                                         '--exclude-standard', '--', str(package)], cwd=repo).decode().split('\0')
        destination = root / name
        manifest = {}
        for relative in sorted(set(filter(None, files))):
            path = Path(relative)
            if path.name == 'pubspec_overrides.yaml':
                continue
            target = destination / path.relative_to(package)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(repo / path, target)
            manifest[str(path.relative_to(package))] = hashlib.sha256(target.read_bytes()).hexdigest()
        (output / f'{name}-export.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
        return destination

    try:
        if args.bundle:
            report['runtime'] = runtime(args.bundle.resolve(), output, stable_flutter_error, windows=True)
        else:
            report['revision'] = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repo, text=True).strip()
            report['source_dirty'] = bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=repo))
            with tempfile.TemporaryDirectory(prefix='apptracer-consumer-') as directory:
                root = Path(directory)
                if args.hosted_desktop:
                    desktop_dep = f'  apptracer_flutter_desktop: {args.hosted_desktop}\n'
                    report['hosted_desktop_version'] = args.hosted_desktop
                else:
                    adapter = export('apptracer_flutter_desktop', root)
                    pubspec = adapter / 'pubspec.yaml'
                    pubspec.write_text(pubspec.read_text(encoding='utf-8').replace('publish_to: none\n', ''), encoding='utf-8')
                    run(['flutter', 'pub', 'get'], adapter)
                    run(['flutter', 'analyze', '--fatal-infos', 'lib', 'test'], adapter)
                    run(['flutter', 'test'], adapter)
                    packed = run(['dart', 'pub', 'publish', '--dry-run'], adapter, sdk_warning=True)
                    for forbidden in ('pubspec_overrides.yaml', '.env.tracer'):
                        assert forbidden not in packed
                    report['adapter_publish_dry_run'] = True
                    desktop_dep = '  apptracer_flutter_desktop:\n    path: ../apptracer_flutter_desktop\n'
                facade_dep = f'  apptracer_flutter: {args.facade_version}\n'
                if args.candidate_facade:
                    facade = export('apptracer_flutter', root)
                    run(['flutter', 'pub', 'get', '--no-example'], facade)
                    run(['flutter', 'analyze', '--fatal-infos', 'lib', 'test'], facade)
                    run(['flutter', 'test'], facade)
                    run(['dart', 'pub', 'publish', '--dry-run'], facade)
                    report['facade_publish_dry_run'] = True
                    facade_dep = '  apptracer_flutter:\n    path: ../apptracer_flutter\n'
                app = root / 'consumer'
                run(['flutter', 'create', '--platforms=windows', '--no-pub', '--project-name',
                     'tracer_external_consumer', str(app)], root)
                (app / 'pubspec.yaml').write_text('name: tracer_external_consumer\npublish_to: none\n'
                    'version: 1.0.0+1\nenvironment:\n  sdk: ^3.5.0\ndependencies:\n'
                    '  flutter:\n    sdk: flutter\n' + facade_dep +
                    desktop_dep +
                    'flutter:\n  uses-material-design: true\n', encoding='utf-8')
                (app / 'lib/main.dart').write_text(MAIN.replace('Ubuntu', 'Windows').replace("stdout.writeln('CONSUMER_OK');", "await File(Platform.environment['TRACER_CONSUMER_DONE']!).writeAsString('CONSUMER_OK');"), encoding='utf-8')
                shutil.rmtree(app / 'test')
                (app / 'analysis_options.yaml').write_text('analyzer:\n  errors:\n    unused_import: error\n', encoding='utf-8')
                cmake = app / 'windows/CMakeLists.txt'
                content = cmake.read_text(encoding='utf-8')
                if args.native_source:
                    source_path = args.native_source.resolve().as_posix()
                    content = content.replace('include(flutter/generated_plugins.cmake)',
                        'set(FETCHCONTENT_SOURCE_DIR_SENTRY-NATIVE "' + source_path + '" CACHE PATH "Pinned local SDK" FORCE)\n'
                        'include(flutter/generated_plugins.cmake)')
                cmake.write_text(content, encoding='utf-8')
                run(['flutter', 'pub', 'get'], app)
                graph = json.loads(run(['dart', 'pub', 'deps', '--json'], app))
                siblings = {p['name']: {'source': p['source'], 'version': p['version']}
                            for p in graph['packages'] if p['name'].startswith('apptracer_')}
                paths = set() if args.hosted_desktop else {'apptracer_flutter_desktop'}
                if args.candidate_facade:
                    paths.add('apptracer_flutter')
                for name, metadata in siblings.items():
                    assert metadata['source'] == ('path' if name in paths else 'hosted'), siblings
                assert not list(root.rglob('pubspec_overrides.yaml'))
                report['dependencies'] = siblings
                shutil.copy2(app / 'pubspec.lock', output / 'consumer.pubspec.lock')
                run(['flutter', 'analyze', '--fatal-infos'], app)
                run(['flutter', 'build', 'windows', '--release', '--obfuscate',
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
