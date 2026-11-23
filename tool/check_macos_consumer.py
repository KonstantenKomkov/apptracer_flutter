#!/usr/bin/env python3
"""Build an external macOS consumer of an isolated desktop package export.

The default consumer resolves published packages from pub.dev. --candidate-facade
checks isolated worktree exports, including publish dry-runs. Never publishes.
"""
import argparse
import gzip
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from consumer_packages import (PUB_DEV, SIBLINGS, check_candidates, check_consumer_graph,
                               consumer_dependencies, consumer_scope, is_sdk_pin_warning, write_overrides)
from check_macos_desktop import envelope_events, read_http_body


MAIN = """import 'dart:io';
import 'package:apptracer_flutter/apptracer_flutter.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  await Tracer.initialize(
    options: TracerOptions(
      dsn: Platform.environment['TRACER_CONSUMER_DSN'],
      release: 'consumer-1',
      initialCustomKeys: const {'consumer': 'external'},
    ),
    appRunner: () {
      runApp(const MaterialApp(home: Text('External consumer')));
      report();
    },
  );
}

Future<void> report() async {
  if (!Tracer.isEnabled ||
      TracerPlatform.instance.backendName != 'sentry-sdk') {
    throw StateError('Desktop plugin did not register automatically');
  }
  await Tracer.setUserId('external-consumer-user');
  Tracer.addBreadcrumb(TracerBreadcrumb(message: 'external consumer started'));
  await Tracer.recordError(
    StateError('external consumer probe'), StackTrace.current);
}
"""


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--candidate-facade', action='store_true')
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    repo = Path(__file__).resolve().parent.parent
    package = Path('packages/apptracer_flutter_desktop')
    report = {'scope': consumer_scope(args.candidate_facade),
              'revision': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repo, text=True).strip(),
              'source_dirty': bool(subprocess.check_output(
                  ['git', 'status', '--porcelain'], cwd=repo, text=True)),
              'success': False}
    env = {key: value for key, value in os.environ.items()
           if not key.startswith('TRACER_')}
    env['PUB_HOSTED_URL'] = PUB_DEV
    env.pop('GEM_HOME', None)
    env.pop('GEM_PATH', None)
    env['COCOAPODS_DISABLE_STATS'] = 'true'
    counter = 0

    def run(command, cwd, allow_sdk_pin_warning=False):
        nonlocal counter
        counter += 1
        log = output / f'{counter:02d}-{command[0]}-{command[1]}.log'
        print('Running: ' + ' '.join(command), flush=True)
        with log.open('w') as stream:
            result = subprocess.run(command, cwd=cwd, env=env, stdout=stream,
                                    stderr=subprocess.STDOUT, timeout=1200)
        content = log.read_text()
        if allow_sdk_pin_warning and is_sdk_pin_warning(result.returncode, content):
            report['publish_warning'] = 'Exact sentry_flutter 9.30.1 pin (intentional; SDK internals are version-specific)'
            print(report['publish_warning'], flush=True)
        elif result.returncode:
            raise RuntimeError(f'Command failed ({result.returncode}); see {log}')
        return content

    try:
        with tempfile.TemporaryDirectory(prefix='tracer external consumer ') as directory:
            root = Path(directory)
            if args.candidate_facade:
                check_candidates(repo, root, output, run, report)
            app = root / 'consumer'
            run(['flutter', 'create', '--platforms=macos', '--no-pub',
                 '--org', 'dev.apptracer.consumer', '--project-name',
                 'tracer_external_consumer', str(app)], root)
            (app / 'pubspec.yaml').write_text(f"""name: tracer_external_consumer
publish_to: none
version: 1.0.0+1
environment:
  sdk: ^3.5.0
dependencies:
  flutter:
    sdk: flutter
{consumer_dependencies(args.candidate_facade)}flutter:
  uses-material-design: true
  config:
    enable-swift-package-manager: false
""")
            if args.candidate_facade:
                write_overrides(app, SIBLINGS)
            (app / 'lib/main.dart').write_text(MAIN)
            shutil.rmtree(app / 'test')
            (app / 'analysis_options.yaml').write_text('analyzer:\n  errors:\n    unused_import: error\n')
            project = app / 'macos/Runner.xcodeproj/project.pbxproj'
            project.write_text(project.read_text().replace('MACOSX_DEPLOYMENT_TARGET = 10.15;',
                                                          'MACOSX_DEPLOYMENT_TARGET = 12.0;'))
            # The generated runner needs network client entitlement in release.
            entitlement = app / 'macos/Runner/Release.entitlements'
            entitlement.write_text(entitlement.read_text().replace(
                '</dict>', '<key>com.apple.security.network.client</key><true/>\n</dict>'))
            # Flutter's CocoaPods template, with the adapter's required minimum.
            shutil.copy2(repo / package / 'example/macos/Podfile', app / 'macos/Podfile')
            run(['flutter', 'pub', 'get'], app)
            graph = json.loads(run(['dart', 'pub', 'deps', '--json'], app))
            check_consumer_graph(graph, root, app, args.candidate_facade, report)
            shutil.copy2(app / 'pubspec.lock', output / 'consumer.pubspec.lock')
            run(['flutter', 'analyze', '--no-pub', '--fatal-infos'], app)
            run(['flutter', 'build', 'macos', '--no-pub', '--release'], app)
            events, failures = [], []

            class Receiver(BaseHTTPRequestHandler):
                def log_message(self, *unused):
                    pass

                def do_POST(self):
                    try:
                        assert self.path == '/api/42/envelope/'
                        data = read_http_body(self.rfile, self.headers)
                        if self.headers.get('Content-Encoding') == 'gzip':
                            data = gzip.decompress(data)
                        for kind, event in envelope_events(data):
                            assert kind == 'event', kind
                            events.append(event)
                        self.send_response(200)
                        self.send_header('Content-Length', '2')
                        self.end_headers()
                        self.wfile.write(b'{}')
                    except Exception as error:
                        failures.append(repr(error))
                        self.send_error(400)

            server = ThreadingHTTPServer(('127.0.0.1', 0), Receiver)
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            binary = app / 'build/macos/Build/Products/Release/tracer_external_consumer.app/Contents/MacOS/tracer_external_consumer'
            try:
                with (output / 'consumer-runtime.log').open('w') as log:
                    child = subprocess.Popen([str(binary)], cwd=binary.parent,
                        env=dict(env, TRACER_CONSUMER_DSN=f'http://consumer@127.0.0.1:{server.server_port}/42'),
                        stdout=log, stderr=subprocess.STDOUT)
                    try:
                        deadline = time.monotonic() + 30
                        while not events and child.poll() is None and time.monotonic() < deadline:
                            time.sleep(0.1)
                        time.sleep(2)
                    finally:
                        if child.poll() is None:
                            child.terminate()
                        try:
                            child.wait(timeout=5)
                        except subprocess.TimeoutExpired:
                            child.kill()
                            child.wait(timeout=5)
            finally:
                server.shutdown()
                server.server_close()
                thread.join(timeout=2)
            report['events'] = events
            assert not failures, failures
            assert len(events) == 1, f'Expected one event, got {len(events)}'
            event = events[0]
            assert 'external consumer probe' in str(event.get('exception'))
            assert event.get('tags', {}).get('consumer') == 'external'
            assert event.get('user', {}).get('id') == 'external-consumer-user'
            assert 'external consumer started' in str(event.get('breadcrumbs'))
            report['success'] = True
    except Exception as error:
        report['error'] = str(error)
        raise
    finally:
        (output / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(f'External consumer passed: {output / "report.json"}')


if __name__ == '__main__':
    main()
