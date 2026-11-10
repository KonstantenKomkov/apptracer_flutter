#!/usr/bin/env python3
"""Clean Flutter/AGP builds for Tracer UUID/upload flags, with uploads blocked."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import xml.etree.ElementTree as ET

ZERO = '00000000-0000-0000-0000-000000000000'
ROOT = Path(__file__).resolve().parents[1]
EXAMPLE = ROOT / 'packages/apptracer_flutter/example'
ANDROID = EXAMPLE / 'android'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ)
    for name in ['TRACER_APP_TOKEN', 'TRACER_PLUGIN_TOKEN', 'DART_SPLIT_DEBUG_INFO']:
        env.pop(name, None)
    env['TRACER_APP_TOKEN'] = 'android-sdk161-build-placeholder'
    sdk = Path(os.environ.get('ANDROID_SDK_ROOT',
               os.environ.get('ANDROID_HOME', Path.home() / 'Library/Android/sdk')))
    aapt = sdk / 'build-tools/36.0.0/aapt2'
    if not aapt.exists():
        raise SystemExit('aapt2 from Android build-tools 36.0.0 is required')
    with (out / 'flutter-config.log').open('w') as log:
        subprocess.run(['flutter', 'build', 'apk', '--release', '--config-only',
                        '--target-platform=android-arm64', '--android-skip-build-dependency-validation'],
                       cwd=EXAMPLE, env=env, stdout=log, stderr=subprocess.STDOUT, check=True)
    base = ['./gradlew', '--console=plain', '--no-build-cache', '--no-configuration-cache',
            '-PskipDependencyChecks=true', '-Ptarget-platform=android-arm64', '-Ptarget=lib/main.dart',
            '-Ptracer.enabled=true', '-Ptracer.deferred=false', '-Ptracer.diagnostics=false',
            '-I', str(ROOT / 'tool/android_no_upload.init.gradle')]
    cases = [('r8-on_mapping-on', True, True, False),
             ('r8-on_mapping-off', True, False, False),
             ('r8-off_mapping-on', False, True, False),
             ('r8-off_mapping-off', False, False, False),
             ('defaults', True, None, None),
             ('r8-on_mapping-off_repeat', True, False, False),
             ('native-only', True, False, True)]
    results = []
    for name, minify, mapping, native in cases:
        print('BUILD', name, flush=True)
        case_env = dict(env)
        if mapping is not False or native is not False:
            case_env['TRACER_PLUGIN_TOKEN'] = 'android-sdk161-plugin-placeholder'
        graph_file = out / (name + '-graph.json')
        command = base + ['-I', str(ROOT / 'tool/android_mapping_graph.init.gradle'),
                          '-Ptracer.verificationGraph=' + str(graph_file),
                          '-Pshrink=' + str(minify).lower()]
        if mapping is not None:
            command += ['-Ptracer.uploadMapping=' + str(mapping).lower()]
        if native is not None:
            command += ['-Ptracer.uploadNativeSymbols=' + str(native).lower()]
        with (out / (name + '.log')).open('w') as log:
            subprocess.run(command + ['clean', ':app:assembleRelease'], cwd=ANDROID, env=case_env,
                           stdout=log, stderr=subprocess.STDOUT, check=True)
        app = EXAMPLE / 'build/app'
        apk = app / 'outputs/apk/release/app-release.apk'
        graph = json.loads(graph_file.read_text())
        resources = app / 'generated/res/resValues/release/values/gradleResValues.xml'
        uuid = ET.parse(resources).find("string[@name='tracer_mapping_uuid']").text
        dump = subprocess.check_output([str(aapt), 'dump', 'resources', str(apk)], text=True)
        match = re.search(r'string/tracer_mapping_uuid\s+\(\) "([^"]+)"', dump)
        assert match and match[1] == uuid, 'APK UUID differs from generated resource'
        should_map = minify and mapping is not False
        assert (uuid != ZERO) == should_map, (name, uuid)
        uploads = [t for t in graph if 'uploadTracerMapping' in t['path']]
        symbols = [t for t in graph if 'generateTracerNativeSymbols' in t['path']]
        assert bool(uploads) == should_map, (name, graph)
        assert bool(symbols) == (native is not False), (name, graph)
        assert all(not t['enabled'] for t in uploads + symbols)
        assert any('minifyReleaseWithR8' in t['path'] for t in graph) == minify
        mapping_path = app / 'outputs/mapping/release/mapping.txt'
        assert mapping_path.exists() == minify
        if uploads:
            assert Path(uploads[0]['mapping']) == mapping_path
            assert ':app:minifyReleaseWithR8' in uploads[0]['dependencies']
        item = {'case': name, 'minified': minify, 'mappingFlag': mapping,
                'nativeFlag': native, 'pluginTokenPresent': 'TRACER_PLUGIN_TOKEN' in case_env,
                'buildUuid': uuid, 'apkSha256': hashlib.sha256(apk.read_bytes()).hexdigest(),
                'resourceSha256': hashlib.sha256(resources.read_bytes()).hexdigest(),
                'mappingUploadTasks': len(uploads), 'nativeUploadTasks': len(symbols),
                'uploadTasksDisabledByGuard': True}
        shutil.copyfile(apk, out / (name + '.apk'))
        if mapping_path.exists():
            item['mappingSha256'] = hashlib.sha256(mapping_path.read_bytes()).hexdigest()
            shutil.copyfile(mapping_path, out / (name + '-mapping.txt'))
        results.append(item)
        (out / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
    first = next(r for r in results if r['case'] == 'r8-on_mapping-off')
    repeat = next(r for r in results if r['case'] == 'r8-on_mapping-off_repeat')
    assert first['buildUuid'] == repeat['buildUuid'] == ZERO
    assert first['resourceSha256'] == repeat['resourceSha256']
    for name, variables, flags, error in [
        ('missing-app-token', {}, ['-Ptracer.uploadMapping=false', '-Ptracer.uploadNativeSymbols=false'], 'requires TRACER_APP_TOKEN'),
        ('missing-mapping-token', env, ['-Ptracer.uploadMapping=true', '-Ptracer.uploadNativeSymbols=false'], 'TRACER_PLUGIN_TOKEN is required'),
        ('missing-native-token', env, ['-Ptracer.uploadMapping=false', '-Ptracer.uploadNativeSymbols=true'], 'TRACER_PLUGIN_TOKEN is required'),
        ('invalid-upload-flag', env, ['-Ptracer.uploadMapping=no', '-Ptracer.uploadNativeSymbols=false'], 'must be true or false'),
    ]:
        check_env = dict(env)
        check_env.pop('TRACER_APP_TOKEN', None)
        check_env.update(variables)
        run = subprocess.run(base + flags + [':app:tasks'], cwd=ANDROID, env=check_env,
                             text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        (out / (name + '.log')).write_text(run.stdout)
        assert run.returncode != 0 and error in run.stdout, name
    print('PASS: UUID/resources/graph/APK matrix, repeat clean build and token gates', flush=True)


if __name__ == '__main__':
    main()
