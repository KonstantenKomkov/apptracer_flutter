#!/usr/bin/env python3
"""Strict cache reuse/invalidation; distinguish the known Flutter assemble blocker."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import xml.etree.ElementTree as ET

from check_android_variants import ROOT, ZERO, prepare_fixture


def run(command, cwd, env, log_path):
    with log_path.open('w') as log:
        result = subprocess.run(command, cwd=cwd, env=env, stdout=log, stderr=subprocess.STDOUT)
    return result.returncode, log_path.read_text()


def resource(project, name):
    path = project / 'app/build/generated/res/resValues/alpha/release/values/gradleResValues.xml'
    if not path.exists():
        return None
    entry = ET.parse(path).find("string[@name='" + name + "']")
    return entry.text if entry is not None else None


def known_flutter_failure(text):
    # Do not turn arbitrary cache/build errors into an accepted limitation.
    problems = [line for line in text.splitlines() if line.startswith('- Task `')]
    return (bool(problems) and all('Task `:app:assembleRelease`' in line for line in problems)
            and 'FlutterPlugin' in text and 'ApkVariantOutputImpl' in text
            and 'Configuration cache entry discarded' in text
            and 'cannot serialize object' in text)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--native-only', action='store_true')
    parser.add_argument('--require-full-flutter', action='store_true')
    args = parser.parse_args()
    if args.native_only and args.require_full_flutter:
        parser.error('--native-only cannot require full Flutter')
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ)
    env['TRACER_APP_TOKEN'] = 'android-cache-placeholder'
    env['TRACER_PLUGIN_TOKEN'] = 'android-plugin-placeholder'
    env.pop('DART_SPLIT_DEBUG_INFO', None)
    guard = ROOT / 'tool/android_no_upload.init.gradle'
    strict = ['--console=plain', '--configuration-cache', '--configuration-cache-problems=fail']
    evidence = {'native': {}, 'fullFlutter': {}}
    for sdk_enabled in [True, False]:
        name = 'sdk' if sdk_enabled else 'no-sdk'
        folder = out / ('native-' + name)
        folder.mkdir()
        project, sdk, wrapper = prepare_fixture(folder)
        properties = project / 'gradle.properties'
        properties.write_text(properties.read_text() + 'tracer.uploadMapping=false\n')
        command = [str(wrapper), '-p', str(project), ':app:assembleAlphaRelease', *strict,
                   '-Ptracer.enabled=' + str(sdk_enabled).lower(), '-I', str(guard)]
        print('NATIVE', name, 'store/reuse', flush=True)
        first, log = run(command, project, env, folder / 'first.log')
        assert first == 0 and 'Configuration cache entry stored' in log, folder / 'first.log'
        second, log = run(command, project, env, folder / 'second.log')
        assert second == 0 and 'Reusing configuration cache.' in log, folder / 'second.log'
        assert 'Configuration cache entry reused.' in log
        assert resource(project, 'tracer_mapping_uuid') == (ZERO if sdk_enabled else None)
        evidence['native'][name] = {'first': 'stored', 'second': 'reused'}
        if sdk_enabled:
            # Same command, changed provider input in gradle.properties; no clean.
            properties.write_text(properties.read_text().replace('tracer.uploadMapping=false', 'tracer.uploadMapping=true'))
            third, log = run(command, project, env, folder / 'invalidated.log')
            assert third == 0 and 'cannot be reused' in log and 'gradle.properties' in log
            assert 'Configuration cache entry stored' in log
            assert ':app:uploadTracerMappingForAlphaRelease SKIPPED' in log
            uuid = resource(project, 'tracer_mapping_uuid')
            assert uuid and uuid != ZERO
            fourth, log = run(command, project, env, folder / 'changed-reused.log')
            assert fourth == 0 and 'Reusing configuration cache.' in log
            assert resource(project, 'tracer_mapping_uuid') == uuid
            evidence['native'][name].update(invalidatedBy='gradle.properties: tracer.uploadMapping false -> true',
                                           newBuildUuid=uuid, changedConfiguration='stored then reused',
                                           enabledMappingTask='SKIPPED by guard')
    if not args.native_only:
        example = ROOT / 'packages/apptracer_flutter/example'
        command = ['flutter', 'build', 'apk', '--release', '--config-only',
                   '--target-platform=android-arm64', '--android-skip-build-dependency-validation']
        code, _ = run(command, example, env, out / 'flutter-config.log')
        assert code == 0
        for sdk_enabled in [True, False]:
            name = 'sdk' if sdk_enabled else 'no-sdk'
            command = ['./gradlew', ':app:assembleRelease', *strict,
                       '--project-cache-dir', str(out / ('flutter-cache-' + name)),
                       '-Ptracer.enabled=' + str(sdk_enabled).lower(),
                       '-Ptracer.uploadMapping=false', '-Ptracer.uploadNativeSymbols=false',
                       '-PskipDependencyChecks=true', '-Ptarget-platform=android-arm64',
                       '-Ptarget=lib/main.dart', '-I', str(guard)]
            print('FLUTTER', name, 'first/second', flush=True)
            first, first_log = run(command, example / 'android', env, out / ('flutter-' + name + '-first.log'))
            second, second_log = run(command, example / 'android', env, out / ('flutter-' + name + '-second.log'))
            if first == 0 and second == 0:
                assert 'Reusing configuration cache.' in second_log
                evidence['fullFlutter'][name] = {'first': 'stored', 'second': 'reused'}
                if sdk_enabled:
                    changed_env = dict(env, TRACER_APP_TOKEN='android-cache-changed-placeholder')
                    third, log = run(command, example / 'android', changed_env, out / 'flutter-sdk-invalidated.log')
                    assert third == 0 and 'cannot be reused' in log and 'TRACER_APP_TOKEN' in log
                    resources = example / 'build/app/generated/res/resValues/release/values/gradleResValues.xml'
                    assert ET.parse(resources).find("string[@name='tracer_app_token']").text == changed_env['TRACER_APP_TOKEN']
                    evidence['fullFlutter'][name]['invalidatedBy'] = 'TRACER_APP_TOKEN'
            else:
                assert first != 0 and second != 0 and known_flutter_failure(first_log) and known_flutter_failure(second_log), 'Unexpected full Flutter failure; inspect logs'
                evidence['fullFlutter'][name] = {'first': 'blocked', 'second': 'blocked',
                    'owner': 'FlutterPlugin assembleRelease action captures ApkVariantOutputImpl',
                    'cache': 'discarded; no reuse claim'}
        statuses = [result['first'] for result in evidence['fullFlutter'].values()]
        assert len(set(statuses)) == 1, 'SDK/no-SDK results differ; cannot attribute solely to Flutter'
        if statuses[0] == 'blocked':
            # Exercise the actual example's provider-based script without the
            # upstream assemble action. This is not an APK-build acceptance.
            command = ['./gradlew', ':app:generateReleaseResValues',
                       ':app:generateTracerManifestSourcesForRelease', *strict,
                       '--project-cache-dir', str(out / 'flutter-config-tasks-cache'),
                       '-Ptracer.enabled=true', '-Ptracer.uploadMapping=false',
                       '-Ptracer.uploadNativeSymbols=false', '-PskipDependencyChecks=true',
                       '-I', str(guard)]
            print('FLUTTER configuration tasks store/reuse/invalidation', flush=True)
            first, log = run(command, example / 'android', env, out / 'flutter-config-tasks-first.log')
            assert first == 0 and 'Configuration cache entry stored' in log
            second, log = run(command, example / 'android', env, out / 'flutter-config-tasks-second.log')
            assert second == 0 and 'Reusing configuration cache.' in log
            changed_env = dict(env, TRACER_APP_TOKEN='android-cache-changed-placeholder')
            third, log = run(command, example / 'android', changed_env, out / 'flutter-config-tasks-invalidated.log')
            assert third == 0 and 'cannot be reused' in log and 'TRACER_APP_TOKEN' in log
            resources = example / 'build/app/generated/res/resValues/release/values/gradleResValues.xml'
            assert ET.parse(resources).find("string[@name='tracer_app_token']").text == changed_env['TRACER_APP_TOKEN']
            evidence['flutterConfigurationTasks'] = {'first': 'stored', 'second': 'reused',
                'invalidatedBy': 'TRACER_APP_TOKEN', 'generatedResourceUpdated': True,
                'scope': 'resource/manifest generation only; assemble remains blocked'}
    (out / 'results.json').write_text(json.dumps(evidence, indent=2) + '\n')
    blocked = any(r['first'] == 'blocked' for r in evidence['fullFlutter'].values())
    if blocked:
        print('LIMITATION: full Flutter cache blocked in SDK and no-SDK by its assemble action; native strict gate passed', flush=True)
        if args.require_full_flutter:
            raise SystemExit(1)
    else:
        print('PASS: strict cache store/reuse/invalidation', flush=True)


if __name__ == '__main__':
    main()
