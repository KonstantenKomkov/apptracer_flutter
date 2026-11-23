"""Package the coordinated desktop candidate outside the checkout for acceptance."""
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess


FACADE = 'apptracer_flutter'
DESKTOP = 'apptracer_flutter_desktop'
SIBLINGS = ('apptracer_flutter_android', 'apptracer_flutter_ios', 'apptracer_flutter_web',
            'apptracer_flutter_http', 'apptracer_flutter_platform_interface')
CANDIDATES = (FACADE, DESKTOP, *SIBLINGS)
PUB_DEV = 'https://pub.dev'
LOCAL_FILES = ('pubspec_overrides.yaml', '.env.tracer')


def consumer_scope(candidate):
    if candidate:
        return 'Staged worktree exports with unpublished siblings; hosted release validation pending publication'
    return 'Published production packages from pub.dev without overrides'


def consumer_dependencies(candidate):
    if candidate:
        return f'  {FACADE}:\n    path: ../{FACADE}\n  {DESKTOP}:\n    path: ../{DESKTOP}\n'
    return f'  {FACADE}: 1.4.0\n  {DESKTOP}: 1.0.1\n'


def export_candidate(repo, root, output, name):
    package = Path('packages') / name
    files = subprocess.check_output(
        ['git', 'ls-files', '-z', '--cached', '--others', '--exclude-standard', '--', str(package)],
        cwd=repo).decode().split('\0')
    manifest = {}
    for relative in sorted(filter(None, files)):
        source = repo / relative
        if source.name in LOCAL_FILES or not source.is_file():
            continue
        local = source.relative_to(repo / package)
        target = root / name / local
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        manifest[str(local)] = hashlib.sha256(target.read_bytes()).hexdigest()
    (output / f'{name}-export.json').write_text(json.dumps(manifest, indent=2) + '\n')


def write_overrides(package, names):
    (package / 'pubspec_overrides.yaml').write_text('dependency_overrides:\n' + ''.join(
        f'  {name}:\n    path: ../{name}\n' for name in names))


def is_sdk_pin_warning(status, log):
    _, marker, validation = log.partition('Validating package...')
    if status != 65 or not marker:
        return False
    warning, _, hints = validation.partition('Package validation found the following hint')
    pin = '* Your dependency on "sentry_flutter" should allow more than one version. For example:'
    summary = re.search(r'^Package has 1 warning(?: and (\d+) hints?)?\.$',
                        validation.rstrip().split('\n')[-1])
    if not summary or re.findall(r'^\* .*$', warning, re.MULTILINE) != [pin]:
        return False
    hint = '* Non-dev dependencies are overridden in pubspec_overrides.yaml.'
    reported_hints = re.findall(r'^\* .*$', hints, re.MULTILINE)
    return (re.search(r'^ +sentry_flutter: \^9\.30\.1$', warning, re.MULTILINE) is not None
            and len(reported_hints) == int(summary[1] or 0)
            and all(item == hint for item in reported_hints))


def check_archive(log, name):
    # Pub also mentions overrides during resolution and in a validation hint.
    match = re.search(rf'^Publishing {re.escape(name)} [^\n]+:\n(.+?)^Total compressed archive size:',
                      log, re.MULTILINE | re.DOTALL)
    if not match or not re.search(r'^\S+ pubspec\.yaml \(', match[1], re.MULTILINE):
        raise ValueError(f'Missing {name} publish archive inventory')
    for forbidden in LOCAL_FILES:
        if forbidden in match[1]:
            raise ValueError(f'{name} publish archive includes {forbidden}')


def check_candidates(repo, root, output, run, report):
    for name in CANDIDATES:
        export_candidate(repo, root, output, name)
    for name, dependencies in ((DESKTOP, (FACADE, *SIBLINGS)), (FACADE, SIBLINGS)):
        package = root / name
        write_overrides(package, dependencies)
        run(['flutter', 'pub', 'get', '--no-example'], package)
        run(['flutter', 'analyze', '--no-pub', '--fatal-infos', 'lib', 'test'], package)
        run(['flutter', 'test', '--no-pub'], package)
        packed = run(['dart', 'pub', 'publish', '--dry-run'], package, name == DESKTOP)
        check_archive(packed, name)
        report['adapter_publish_dry_run' if name == DESKTOP else 'facade_publish_dry_run'] = True


def check_consumer_graph(graph, root, app, candidate, report):
    siblings = {p['name']: {'source': p['source'], 'version': p['version']}
                for p in graph['packages'] if p['name'].startswith('apptracer_')}
    if not set(CANDIDATES).issubset(siblings):
        raise ValueError(f'Missing consumer dependencies: {set(CANDIDATES) - siblings.keys()}')
    for package in graph['packages']:
        name = package['name']
        source = package['source']
        if name not in siblings and (source == 'sdk' or (source == 'root' and name == graph['root'])):
            continue
        expected = 'path' if candidate and name in CANDIDATES else 'hosted'
        if source != expected:
            raise ValueError(f'{name} resolved from {source}, expected {expected}')
    # Pub's JSON graph omits registry URLs. Check each hosted entry in its generated lockfile.
    urls = re.findall(r'^      url: (.+)$', (app / 'pubspec.lock').read_text(), re.MULTILINE)
    hosted_count = sum(p['source'] == 'hosted' for p in graph['packages'])
    if len(urls) != hosted_count or any(url not in (PUB_DEV, f'"{PUB_DEV}"') for url in urls):
        raise ValueError('Expected every hosted dependency to resolve from pub.dev')
    expected_roots = (root / DESKTOP, root / FACADE, app) if candidate else ()
    overrides = set(root.rglob('pubspec_overrides.yaml'))
    if overrides != {pkg / 'pubspec_overrides.yaml' for pkg in expected_roots}:
        raise ValueError(f'Unexpected override inventory: {overrides}')
    report['candidate_dependency_overrides'] = [str(p.relative_to(root)) for p in sorted(overrides)]
    report['dependencies'] = siblings
