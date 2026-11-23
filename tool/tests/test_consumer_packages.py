import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from consumer_packages import (CANDIDATES, DESKTOP, FACADE, PUB_DEV, check_archive,
                               check_consumer_graph, export_candidate, is_sdk_pin_warning)


class ConsumerPackageTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.app = self.root / 'consumer'
        self.app.mkdir()

    def check_graph(self, candidate, source, registry=PUB_DEV, transitive='hosted', sdk=None):
        versions = {DESKTOP: '2.0.0' if candidate else '1.0.1'}
        graph = {'packages': [{'name': name, 'source': source, 'version': versions.get(name, '1.0.0')}
                              for name in CANDIDATES]}
        graph['packages'].append({'name': 'sentry_flutter', 'source': transitive,
                                  'version': sdk or ('10.6.0' if candidate else '9.30.1')})
        (self.app / 'pubspec.lock').write_text('packages:\n' + ''.join(
            f'  {p["name"]}:\n    description:\n      url: "{registry}"\n    source: hosted\n'
            for p in graph['packages'] if p['source'] == 'hosted'))
        report = {}
        check_consumer_graph(graph, self.root, self.app, candidate, report)
        return report['candidate_dependency_overrides']

    def test_hosted_consumer_rejects_overrides_even_with_a_hosted_graph(self):
        self.assertEqual(self.check_graph(False, 'hosted'), [])
        (self.app / 'pubspec_overrides.yaml').touch()
        with self.assertRaisesRegex(ValueError, 'override inventory'):
            self.check_graph(False, 'hosted')

    def test_hosted_rejects_a_mirror_or_non_hosted_transitive_dependency(self):
        with self.assertRaisesRegex(ValueError, 'pub.dev'):
            self.check_graph(False, 'hosted', registry='https://mirror.example')
        with self.assertRaisesRegex(ValueError, 'sentry_flutter resolved from git'):
            self.check_graph(False, 'hosted', transitive='git')

    def test_consumer_rejects_sdk_from_the_other_release(self):
        for candidate, source, sdk in [(False, 'hosted', '10.6.0'), (True, 'path', '9.30.1')]:
            with self.subTest(candidate=candidate), self.assertRaisesRegex(ValueError, 'Expected sentry_flutter'):
                self.check_graph(candidate, source, sdk=sdk)

    def test_manifest_records_worktree_contents_and_excludes_local_files(self):
        repo = self.root / 'repo'
        package = repo / 'packages' / FACADE
        lib = package / 'lib'
        lib.mkdir(parents=True)
        source = lib / 'facade.dart'
        source.write_bytes(b'original')
        (lib / '.env.tracer').write_text('fixture')
        (package / 'pubspec_overrides.yaml').write_text('fixture')
        subprocess.run(['git', 'init', '--quiet'], cwd=repo, check=True)
        subprocess.run(['git', 'add', '--force', 'packages'], cwd=repo, check=True)
        source.write_bytes(b'worktree')
        (lib / 'new.dart').write_bytes(b'new')
        export_candidate(repo, self.root, self.app, FACADE)
        manifest = json.loads((self.app / f'{FACADE}-export.json').read_text())
        for path in (source, lib / 'new.dart'):
            relative = path.relative_to(package)
            self.assertEqual((self.root / FACADE / relative).read_bytes(), path.read_bytes())
            self.assertEqual(manifest.pop(str(relative)), hashlib.sha256(path.read_bytes()).hexdigest())
        self.assertEqual(manifest, {})
        self.assertFalse((self.root / FACADE / 'lib/.env.tracer').exists())
        self.assertFalse((self.root / FACADE / 'pubspec_overrides.yaml').exists())

    def test_candidate_requires_path_exports_and_only_known_overrides(self):
        for name in (DESKTOP, FACADE):
            (self.root / name).mkdir()
        for package in (self.root / DESKTOP, self.root / FACADE, self.app):
            (package / 'pubspec_overrides.yaml').touch()
        self.assertEqual(len(self.check_graph(True, 'path')), 3)
        with self.assertRaisesRegex(ValueError, 'expected path'):
            self.check_graph(True, 'hosted')
        with self.assertRaisesRegex(ValueError, 'expected hosted'):
            self.check_graph(False, 'path')
        (self.root / 'pubspec_overrides.yaml').touch()
        with self.assertRaisesRegex(ValueError, 'override inventory'):
            self.check_graph(True, 'path')

    def test_dry_run_distinguishes_resolution_hint_from_archive_contents(self):
        listing = 'Publishing adapter 1.0.0 to https://pub.dev:\n└── pubspec.yaml (<1 KB)\n'
        hint = ('Total compressed archive size: 1 KB.\nValidating package...\n'
                '* Non-dev dependencies are overridden in pubspec_overrides.yaml.')
        check_archive(listing + hint, 'adapter')
        for name in ('pubspec_overrides.yaml', '.env.tracer'):
            with self.subTest(name=name), self.assertRaisesRegex(ValueError, 'archive includes'):
                check_archive(listing + f'└── {name}\n' + hint, 'adapter')
        with self.assertRaisesRegex(ValueError, 'Missing'):
            check_archive(hint, 'adapter')

    def test_sdk_pin_with_override_hint_does_not_excuse_other_warnings_or_errors(self):
        pin = ('Validating package...\n* Your dependency on "sentry_flutter" should allow more '
               'than one version. For example:\n    sentry_flutter: ^10.6.0\n')
        hint = ('Package validation found the following hint:\n'
                '* Non-dev dependencies are overridden in pubspec_overrides.yaml.\n')
        summary_with_hint = 'Package has 1 warning and 1 hint.'
        self.assertTrue(is_sdk_pin_warning(65, pin + 'Package has 1 warning.'))
        self.assertTrue(is_sdk_pin_warning(65, pin + hint + summary_with_hint))
        self.assertFalse(is_sdk_pin_warning(65, pin + '* Another warning.\n' + hint + summary_with_hint))
        self.assertFalse(is_sdk_pin_warning(65, pin.replace('10.6.0', '9.30.1') + hint + summary_with_hint))
        for summary in ('Package has 2 warnings and 1 hint.', 'Package has 1 error and 1 warning.'):
            self.assertFalse(is_sdk_pin_warning(65, pin + summary))
        self.assertFalse(is_sdk_pin_warning(1, pin + 'Package has 1 warning.'))


if __name__ == '__main__':
    unittest.main()
