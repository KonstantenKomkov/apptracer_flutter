import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).parents[1] / 'sentry_candidate_report.py'


class CandidateReportTest(unittest.TestCase):
    def report(self, precheck='success', linux='success'):
        directory = Path(tempfile.mkdtemp())
        lock = directory / 'pubspec.lock'
        lock.write_text('  sentry_flutter:\n    version: "10.6.0"\n')
        output = directory / 'report.json'
        subprocess.run([
            sys.executable, str(SCRIPT), '--lock', str(lock), '--precheck', precheck,
            '--linux', linux, '--macos', 'success', '--windows', 'success',
            '--symbols', 'success', '--output', str(output),
        ], check=True, capture_output=True, text=True)
        return json.loads(output.read_text())

    def test_all_operating_systems_and_scenarios_are_explicit(self):
        report = self.report()
        self.assertEqual(report['overall'], 'passed')
        self.assertEqual(report['candidate'], '10.6.0')
        self.assertEqual(set(report['operatingSystems']), {'linux', 'macos', 'windows'})
        for operating_system in report['operatingSystems'].values():
            self.assertEqual(operating_system['status'], 'passed')
            self.assertIn('native_crash', operating_system['stages'])
            self.assertIn('missing_mismatched_symbols', operating_system['stages'])

    def test_failed_precheck_blocks_runtime_and_failed_os_is_visible(self):
        blocked = self.report(precheck='failure')
        self.assertEqual(blocked['overall'], 'failed')
        self.assertTrue(all(value['status'] == 'blocked'
                            for value in blocked['operatingSystems'].values()))
        failed = self.report(linux='failure')
        self.assertEqual(failed['operatingSystems']['linux']['status'], 'failed')
        self.assertEqual(failed['operatingSystems']['macos']['status'], 'passed')


if __name__ == '__main__':
    unittest.main()
