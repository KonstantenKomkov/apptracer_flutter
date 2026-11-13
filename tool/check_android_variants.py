#!/usr/bin/env python3
"""Exercise the real AGP AnalyticsEnabledApplicationVariant with Tracer 1.6.1."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
ZERO = '00000000-0000-0000-0000-000000000000'


def prepare_fixture(output):
    project = output / 'project'
    if project.exists():
        raise RuntimeError('Use a new output directory; fixture already exists: ' + str(project))
    shutil.copytree(ROOT / 'tool/fixtures/android-sdk161', project)
    sdk = Path(os.environ.get('ANDROID_SDK_ROOT',
               os.environ.get('ANDROID_HOME', Path.home() / 'Library/Android/sdk'))).resolve()
    (project / 'local.properties').write_text('sdk.dir=' + str(sdk) + '\n')
    example = ROOT / 'packages/apptracer_flutter/example'
    wrapper = example / 'android/gradlew'
    # Flutter generates these ignored files; a clean CI checkout has neither.
    # Generate configuration only, before the native fixture invokes Gradle.
    wrapper_jar = example / 'android/gradle/wrapper/gradle-wrapper.jar'
    if not wrapper.is_file() or not wrapper_jar.is_file():
        subprocess.run([
            'flutter', 'build', 'apk', '--release', '--config-only',
            '--target-platform=android-arm64',
            '--android-skip-build-dependency-validation',
        ], cwd=example, check=True)
    if not wrapper.is_file() or not wrapper_jar.is_file():
        raise RuntimeError('Flutter did not generate the Android Gradle wrapper')
    return project, sdk, wrapper


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=True)
    project, sdk, wrapper = prepare_fixture(out)
    results = []
    for mappings in [True, False]:
        phase = 'mappings-on' if mappings else 'mappings-off'
        graph_path = out / (phase + '-graph.json')
        command = [str(wrapper), '-p', str(project), '--console=plain',
                   '--no-configuration-cache', '--no-build-cache',
                   '-Pandroid.enableProfileJson=true', '-Ptracer.enabled=true',
                   '-Ptracer.uploadMapping=' + str(mappings).lower(),
                   '-Ptracer.verificationGraph=' + str(graph_path),
                   '-I', str(ROOT / 'tool/android_no_upload.init.gradle'),
                   '-I', str(ROOT / 'tool/android_variant_graph.init.gradle'),
                   ':app:clean']
        command += [':app:assemble' + f.title() + b.title()
                    for f in ['alpha', 'beta'] for b in ['debug', 'release']]
        print('BUILD', phase, flush=True)
        with (out / (phase + '.log')).open('w') as log:
            subprocess.run(command, cwd=project, stdout=log, stderr=subprocess.STDOUT, check=True)
        graph = json.loads(graph_path.read_text())
        assert len(graph['variants']) == 4
        assert all('AnalyticsEnabledApplicationVariant' in v['type'] for v in graph['variants'].values())
        assert len(graph['uploads']) == (2 if mappings else 0)
        uuids = []
        phase_rows = []
        for flavor in ['alpha', 'beta']:
            for build_type in ['debug', 'release']:
                name = flavor + build_type.title()
                app = project / 'app/build'
                apk = app / f'outputs/apk/{flavor}/{build_type}/app-{flavor}-{build_type}.apk'
                resources = app / f'generated/res/resValues/{flavor}/{build_type}/values/gradleResValues.xml'
                uuid = ET.parse(resources).find("string[@name='tracer_mapping_uuid']").text
                dump = subprocess.check_output([str(sdk / 'build-tools/36.0.0/aapt2'), 'dump', 'resources', str(apk)], text=True)
                assert re.search(r'string/tracer_mapping_uuid\s+\(\) "([^"]+)"', dump)[1] == uuid
                enabled = mappings and build_type == 'release'
                assert (uuid != ZERO) == enabled
                mapping_file = app / f'outputs/mapping/{name}/mapping.txt'
                assert mapping_file.exists() == (build_type == 'release')
                row = {'variant': name, 'wrapper': graph['variants'][name]['type'],
                       'applicationId': graph['variants'][name]['applicationId'],
                       'buildUuid': uuid, 'apkSha256': hashlib.sha256(apk.read_bytes()).hexdigest()}
                if build_type == 'release':
                    mapping = mapping_file.read_text()
                    assert all('audit.tracer161.' + flavor.title() + language + 'Failure ->' in mapping
                               for language in ['Java', 'Kotlin'])
                    other = 'Beta' if flavor == 'alpha' else 'Alpha'
                    assert 'audit.tracer161.' + other + 'JavaFailure ->' not in mapping
                    row['mappingSha256'] = hashlib.sha256(mapping_file.read_bytes()).hexdigest()
                    shutil.copyfile(mapping_file, out / (phase + '-' + name + '-mapping.txt'))
                if enabled:
                    upload = next(t for t in graph['uploads'] if t['path'].endswith('For' + name[0].upper() + name[1:]))
                    assert not upload['enabled']
                    assert Path(upload['mapping']) == mapping_file
                    assert upload['buildUuid'] == uuid
                    assert upload['applicationId'] == row['applicationId']
                    assert ':app:minify' + name[0].upper() + name[1:] + 'WithR8' in upload['dependencies']
                    uuids.append(uuid)
                shutil.copyfile(apk, out / (phase + '-' + name + '.apk'))
                phase_rows.append(row)
        if mappings:
            assert len(set(uuids)) == 2
        assert len({r['mappingSha256'] for r in phase_rows if 'mappingSha256' in r}) == 2
        # Make evidence portable without retaining local absolute input paths.
        for upload in graph['uploads']:
            upload['mapping'] = str(Path(upload['mapping']).relative_to(project))
        results.append({'mappingUpload': mappings, 'variants': phase_rows, 'graph': graph})
        (out / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
    print('PASS: real analytics wrappers, variant-specific mapping/UUID, upload-off and debug controls', flush=True)


if __name__ == '__main__':
    main()
