import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from sentry_candidate import apply_version
from sentry_candidate_report import make_report, PLATFORMS


class CandidateTest(unittest.TestCase):
    def setUp(self):
        self.version = '10.6.0'
        self.needs = {
            'select': {'result': 'success', 'outputs': {'version': self.version}},
            'precheck': {'result': 'success', 'outputs': {}},
        }
        self.jobs = []
        for runner, suites in PLATFORMS.values():
            for key, name in {'precheck': f'Precheck ({runner})', **suites}.items():
                self.jobs.append({'name': name, 'conclusion': 'success', 'steps': []})
                if key != 'precheck':
                    self.needs[key] = {'result': 'success', 'outputs': {
                        'versions': json.dumps({'sentryFlutter': self.version, 'flutter': '3.47.4',
                            'dart': '3.13.3', 'sentryCocoa': '9.35.0', 'sentryCocoaRevision': 'a' * 40,
                            'sentryNative': '0.17.6', 'sentryNativeSha256': 'a' * 64})}}

    def test_identical_candidate_passes(self):
        report = make_report(self.needs, self.jobs)
        self.assertEqual(report['overall'], 'passed')
        self.assertEqual(report['candidate'], self.version)

    def test_missing_or_mismatched_build_evidence_fails(self):
        for outputs in [{}, {'versions': '{"sentryFlutter":"9.30.1"}'}]:
            self.needs['windows']['outputs'] = outputs
            report = make_report(self.needs, self.jobs)
            self.assertEqual(report['overall'], 'failed')
            self.assertFalse(report['operatingSystems']['windows']['passed'])

    def test_native_identity_is_required_for_each_build(self):
        for job, field in [('macos', 'sentryCocoaRevision'), ('symbols', 'sentryCocoa'),
                           ('windows', 'sentryNativeSha256'), ('linux', 'sentryNative')]:
            outputs = self.needs[job]['outputs']
            original = outputs['versions']
            versions = json.loads(original)
            del versions[field]
            outputs['versions'] = json.dumps(versions)
            self.assertEqual(make_report(self.needs, self.jobs)['overall'], 'failed')
            outputs['versions'] = original

    def test_skipped_runtime_and_failed_symbols_are_distinct(self):
        self.needs['windows-runtime']['result'] = 'skipped'
        jobs = [job for job in self.jobs if 'Windows native runtime' not in job['name']]
        symbol_job = next(job for job in jobs if 'exact-build symbols' in job['name'])
        symbol_job.update(conclusion='failure', steps=[{'name': 'Decode', 'conclusion': 'skipped'}])
        report = make_report(self.needs, jobs)
        self.assertEqual(report['overall'], 'failed')
        systems = report['operatingSystems']
        self.assertEqual(systems['windows']['stages']['windows-runtime']['status'], 'skipped')
        self.assertEqual(systems['macos']['stages']['symbols']['steps'][0]['conclusion'], 'skipped')
        self.assertTrue(systems['linux']['passed'])

    def test_no_jobs_or_resolution_is_inconclusive(self):
        self.needs['select'] = {'result': 'failure', 'outputs': {}}
        report = make_report(self.needs, [])
        self.assertIsNone(report['candidate'])
        self.assertEqual(report['overall'], 'failed')

    def test_apply_only_replaces_an_exact_pin(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'pubspec.yaml'
            for old, new in [('^9.30.1', self.version), ('9.30.1', 'any'), ('9.30.1', '1.0.0\n')]:
                original = f'dependencies:\n  sentry_flutter: {old}\n'
                path.write_text(original)
                with self.assertRaises(ValueError):
                    apply_version(path, new)
                self.assertEqual(path.read_text(), original)
            apply_version(path, self.version)
            self.assertEqual(path.read_text(), 'dependencies:\n  sentry_flutter: 10.6.0\n')
