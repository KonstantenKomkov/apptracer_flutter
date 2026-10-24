#!/usr/bin/env python3
"""Verify isolated Ubuntu package exports, publish dry-runs and a release consumer.

Uses only a loopback DSN. --candidate-facade stages the unreleased FlutterError
fix as facade 0.2.2; otherwise the facade resolves from pub.dev. Never publishes.
--bundle runs the exported consumer on a separate Ubuntu machine without tools.
"""
import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tarfile
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from check_macos_desktop import envelope_items, read_http_body


MAIN = r"""import 'dart:io';
import 'package:apptracer_flutter/apptracer_flutter.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  var runners = 0;
  await Tracer.initialize(
    options: TracerOptions(
      dsn: Platform.environment['TRACER_CONSUMER_DSN'],
      release: 'ubuntu-external-consumer-1',
      initialCustomKeys: const {'private-key': 'private-value'},
      beforeBreadcrumb: (crumb) => crumb.message == 'private-crumb' ? null : crumb,
      beforeSend: (event) => event.message == 'drop-probe'
          ? null
          : event.message.contains('private-message')
              ? event.copyWith(message: 'redacted', customKeys: {},
                  removeBreadcrumbs: true, stackTrace: DartStackTrace.parse(''))
              : event,
    ),
    appRunner: () {
      runners++;
      runApp(const MaterialApp(home: Text('Ubuntu external consumer')));
    },
  );
  if (runners != 1 || !Tracer.isEnabled ||
      TracerPlatform.instance.backendName != 'sentry-sdk') {
    throw StateError('Automatic registration/start/appRunner failed');
  }
  await Tracer.setUserId('external-consumer-user');
  Tracer.addBreadcrumb(TracerBreadcrumb(message: 'private-crumb'));
  Tracer.addBreadcrumb(TracerBreadcrumb(message: 'visible-crumb'));
  final error = StateError('private-message');
  final stack = StackTrace.current;
  await Tracer.recordError(error, stack);
  await Tracer.recordError(error, stack);
  await Tracer.recordError('drop-probe', StackTrace.current);
  await Tracer.removeCustomKey('private-key');
  await Tracer.setCustomKey(key: 'consumer', value: 'external');
  await Tracer.recordError(StateError('source-probe'), StackTrace.current);
  await Tracer.recordError(FlutterError('external flutter probe'), StackTrace.current);
  await Future<void>.delayed(const Duration(seconds: 3));
  final stopped = await Tracer.stopAndClearCollection();
  if (stopped.state != TracerCollectionState.restartRequired) {
    throw StateError('Consumer clear failed: ${stopped.state}');
  }
  await Tracer.recordError('after-stop-probe', StackTrace.current);
  stdout.writeln('CONSUMER_OK');
  exit(0);
}
"""


def runtime(bundle, output, candidate):
    """Exercise the installed executable, not the source tree."""
    events, errors, kinds = [], [], []

    class Receiver(BaseHTTPRequestHandler):
        def log_message(self, *unused):
            pass

        def do_POST(self):
            try:
                if self.path != '/api/42/envelope/':
                    raise AssertionError('Unexpected endpoint')
                body = read_http_body(self.rfile, self.headers)
                if self.headers.get('Content-Encoding') == 'gzip':
                    body = gzip.decompress(body)
                for header, payload in envelope_items(body):
                    kinds.append(header['type'])
                    if header['type'] != 'event':
                        raise AssertionError('Unexpected SDK telemetry item')
                    events.append(json.loads(payload))
                self.send_response(200)
                self.send_header('Content-Length', '2')
                self.end_headers()
                self.wfile.write(b'{}')
            except Exception as error:
                errors.append(str(error))
                self.send_error(400)

    server = ThreadingHTTPServer(('127.0.0.1', 0), Receiver)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        with tempfile.TemporaryDirectory(prefix='Ubuntu consumer Кириллица ') as directory:
            root = Path(directory)
            installed = root / 'application'
            shutil.copytree(bundle, installed)
            env = {k: v for k, v in os.environ.items() if not k.startswith('TRACER_')}
            env.update(TRACER_CONSUMER_DSN=f'http://consumer@127.0.0.1:{server.server_port}/42',
                       XDG_DATA_HOME=str(root / 'data'), GDK_BACKEND='x11',
                       LIBGL_ALWAYS_SOFTWARE='1')
            with (output / 'runtime.log').open('w') as log:
                child = subprocess.Popen([str(installed / 'tracer_external_consumer')],
                                         cwd=root, env=env, stdout=log,
                                         stderr=subprocess.STDOUT, start_new_session=True)
                try:
                    result = child.wait(timeout=60)
                finally:
                    # Includes the owned SDK daemon on failure; never other apps.
                    try:
                        os.killpg(child.pid, signal.SIGTERM)
                    except ProcessLookupError:
                        pass
                    child.wait(timeout=10)
            assert result == 0, 'Consumer failed; see runtime.log'
            assert 'CONSUMER_OK' in (output / 'runtime.log').read_text()
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)
    (output / 'events.json').write_text(json.dumps(events, indent=2) + '\n')
    assert not errors, errors
    assert len(events) == 3, f'Expected 3 events after filtering/deduplication, got {len(events)}'
    assert kinds == ['event'] * 3, kinds
    redacted = [e for e in events if e['exception']['values'][0]['value'] == 'redacted']
    assert len(redacted) == 1, 'Duplicate event or redaction failure'
    event = redacted[0]
    assert not event.get('tags') and not event.get('breadcrumbs')
    assert not event['exception']['values'][0].get('stacktrace')
    assert not event['contexts']['apptracer']['dart_stack_trace']
    wire = json.dumps(events)
    for forbidden in ('private-value', 'private-message', 'private-crumb', 'drop-probe', 'after-stop-probe'):
        assert forbidden not in wire, f'Filtered data resurrected: {forbidden}'
    for event in events:
        assert event.get('user', {}).get('id') == 'external-consumer-user'
    source = next(e for e in events if 'source-probe' in e['exception']['values'][0]['value'])
    assert source['tags']['consumer'] == 'external'
    assert 'visible-crumb' in json.dumps(source['breadcrumbs'])
    frames = source['exception']['values'][0]['stacktrace']['frames']
    assert any(f.get('filename', '').endswith('main.dart') and f.get('lineno') for f in frames)
    flutter = next(e['exception']['values'][0] for e in events
                   if 'external flutter probe' in e['exception']['values'][0]['value'])
    if candidate:
        assert flutter['type'] == 'FlutterError', flutter['type']
    return {'events': len(events), 'filtering_and_deduplication': True,
            'source_frames': True, 'stop_clear': True, 'unexpected_telemetry': False,
            'flutter_error_type': flutter['type'], 'candidate_facade': candidate}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--candidate-facade', action='store_true')
    parser.add_argument('--bundle', type=Path, help='Only run a previously built consumer bundle')
    args = parser.parse_args()
    if sys.platform != 'linux':
        parser.error('Run on Ubuntu x86_64')
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    report = {'success': False, 'published': False}
    repo = Path(__file__).resolve().parent.parent
    env = {k: v for k, v in os.environ.items() if not k.startswith('TRACER_')}
    env['SENTRY_NATIVE_BACKEND'] = 'native'
    counter = 0

    def run(command, cwd, sdk_warning=False):
        nonlocal counter
        counter += 1
        log = output / f'{counter:02d}-{Path(command[0]).name}.log'
        print('Running: ' + ' '.join(map(str, command)), flush=True)
        with log.open('w') as stream:
            result = subprocess.run(command, cwd=cwd, env=env, stdout=stream,
                                    stderr=subprocess.STDOUT, timeout=1200)
        content = log.read_text()
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
        (output / f'{name}-export.json').write_text(json.dumps(manifest, indent=2) + '\n')
        return destination

    try:
        if args.bundle:
            report['runtime'] = runtime(args.bundle.resolve(), output, args.candidate_facade)
        else:
            report['revision'] = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repo, text=True).strip()
            report['source_dirty'] = bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=repo))
            with tempfile.TemporaryDirectory(prefix='apptracer-consumer-') as directory:
                root = Path(directory)
                adapter = export('apptracer_flutter_desktop', root)
                pubspec = adapter / 'pubspec.yaml'
                pubspec.write_text(pubspec.read_text().replace('publish_to: none\n', ''))
                run(['flutter', 'pub', 'get'], adapter)
                run(['flutter', 'analyze', '--fatal-infos', 'lib', 'test'], adapter)
                run(['flutter', 'test'], adapter)
                packed = run(['dart', 'pub', 'publish', '--dry-run'], adapter, sdk_warning=True)
                for forbidden in ('pubspec_overrides.yaml', '.env.tracer'):
                    assert forbidden not in packed
                report['adapter_publish_dry_run'] = True
                facade_dep = '  apptracer_flutter: 0.2.1\n'
                if args.candidate_facade:
                    facade = export('apptracer_flutter', root)
                    spec = facade / 'pubspec.yaml'
                    spec.write_text(spec.read_text().replace('version: 0.2.1\n', 'version: 0.2.2\n'))
                    changelog = facade / 'CHANGELOG.md'
                    changelog.write_text(changelog.read_text().replace('## [Unreleased]', '## [0.2.2] - 2026-10-24'))
                    run(['flutter', 'pub', 'get', '--no-example'], facade)
                    run(['flutter', 'analyze', '--fatal-infos', 'lib', 'test'], facade)
                    run(['flutter', 'test'], facade)
                    run(['dart', 'pub', 'publish', '--dry-run'], facade)
                    report['facade_publish_dry_run'] = True
                    facade_dep = '  apptracer_flutter:\n    path: ../apptracer_flutter\n'
                app = root / 'consumer'
                run(['flutter', 'create', '--platforms=linux', '--no-pub', '--project-name',
                     'tracer_external_consumer', str(app)], root)
                (app / 'pubspec.yaml').write_text('name: tracer_external_consumer\npublish_to: none\n'
                    'version: 1.0.0+1\nenvironment:\n  sdk: ^3.5.0\ndependencies:\n'
                    '  flutter:\n    sdk: flutter\n' + facade_dep +
                    '  apptracer_flutter_desktop:\n    path: ../apptracer_flutter_desktop\n'
                    'flutter:\n  uses-material-design: true\n')
                (app / 'lib/main.dart').write_text(MAIN)
                shutil.rmtree(app / 'test')
                (app / 'analysis_options.yaml').write_text('analyzer:\n  errors:\n    unused_import: error\n')
                cmake = app / 'linux/CMakeLists.txt'
                content = cmake.read_text()
                # JNI changes CMake's default-prefix marker before Flutter's template
                # processes it. Establish the intended destination before plugins.
                content = content.replace('project(runner LANGUAGES CXX)',
                    'project(runner LANGUAGES CXX)\n'
                    'if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)\n'
                    '  set(CMAKE_INSTALL_PREFIX "${PROJECT_BINARY_DIR}/bundle" CACHE PATH "Bundle" FORCE)\n'
                    'endif()')
                content = content.replace('foreach(bundled_library ${PLUGIN_BUNDLED_LIBRARIES})',
                    'foreach(bundled_library ${PLUGIN_BUNDLED_LIBRARIES})\n'
                    '  if(bundled_library STREQUAL "$<TARGET_FILE:jni>")\n'
                    '    continue()\n  endif()')
                content += '\nadd_dependencies(${BINARY_NAME} sentry-crash)\n'
                content += ('install(PROGRAMS "$<TARGET_FILE:sentry-crash>" '
                            'DESTINATION "${INSTALL_BUNDLE_LIB_DIR}" COMPONENT Runtime)\n')
                cmake.write_text(content)
                runner = app / 'linux/runner/CMakeLists.txt'
                runner.write_text(runner.read_text() + '\ntarget_compile_options(${BINARY_NAME} PRIVATE -g)\n')
                run(['flutter', 'pub', 'get'], app)
                graph = json.loads(run(['dart', 'pub', 'deps', '--json'], app))
                siblings = {p['name']: {'source': p['source'], 'version': p['version']}
                            for p in graph['packages'] if p['name'].startswith('apptracer_')}
                paths = {'apptracer_flutter_desktop'}
                if args.candidate_facade:
                    paths.add('apptracer_flutter')
                for name, metadata in siblings.items():
                    assert metadata['source'] == ('path' if name in paths else 'hosted'), siblings
                assert not list(root.rglob('pubspec_overrides.yaml'))
                report['dependencies'] = siblings
                shutil.copy2(app / 'pubspec.lock', output / 'consumer.pubspec.lock')
                run(['flutter', 'analyze', '--fatal-infos'], app)
                run(['flutter', 'build', 'linux', '--release', '--obfuscate',
                     '--split-debug-info=build/symbols'], app)
                bundle = app / 'build/linux/x64/release/bundle'
                assert os.access(bundle / 'lib/sentry-crash', os.X_OK)
                tools = output / 'symbol-tools'
                run([sys.executable, str(repo / 'tool/prepare_linux_symbol_tools.py'), '--output', str(tools)], root)
                run([sys.executable, str(repo / 'tool/prepare_linux_runtime_symbols.py'), '--bundle', str(bundle),
                     '--executable', 'tracer_external_consumer', '--dump-syms', str(tools / 'dump_syms')], root)
                run([sys.executable, str(repo / 'tool/prepare_linux_dart_runtime_symbols.py'), '--bundle', str(bundle),
                     '--symbols', str(app / 'build/symbols/app.linux-x64.symbols'),
                     '--dump-syms', str(tools / 'dump_syms')], root)
                for binary in [bundle / 'tracer_external_consumer', bundle / 'lib/sentry-crash',
                               *sorted((bundle / 'lib').glob('*.so'))]:
                    assert 'not found' not in run(['ldd', str(binary)], root)
                archive = output / 'consumer-bundle.tar.gz'
                with tarfile.open(archive, 'w:gz') as tar:
                    tar.add(bundle, arcname='bundle')
                report['bundle_sha256'] = hashlib.sha256(archive.read_bytes()).hexdigest()
                shutil.copytree(app / 'build/symbols', output / 'symbols', dirs_exist_ok=True)
                report['runtime'] = runtime(bundle, output, args.candidate_facade)
        report['success'] = True
    except Exception as error:
        report['error'] = str(error)
        raise
    finally:
        (output / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
