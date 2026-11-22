import contextlib
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import coverage_report as report


class CoverageReportTest(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.output = self.root / 'build/coverage'
        self.baseline = self.root / 'tool/coverage_baseline.json'
        self.baseline.parent.mkdir()
        self.baseline.write_text(json.dumps({
            path: {'covered': 1, 'total': 2} for path in report.CRITICAL.values()
        }))
        paths = list(report.CRITICAL.values()) + [
            f'{report.DESKTOP}/lib/src/{name}.dart'
            for name in ('shared', 'linux_storage', 'windows_storage', 'macos_lifecycle')
        ]
        rows = {}
        for path in paths:
            package, source = path.split('/lib/')
            rows[package] = {'path': package, 'vm': 'true'}
            library = self.root / path
            library.parent.mkdir(parents=True, exist_ok=True)
            library.touch()
            lcov = self.root / package / 'coverage/lcov.info'
            lcov.parent.mkdir(exist_ok=True)
            with lcov.open('a') as f:
                f.write(f'SF:lib/{source}\nDA:1,1\nDA:2,0\nend_of_record\n')
        self.addCleanup(patch.stopall)
        patch.object(report, 'ROOT', self.root).start()
        patch.object(report, 'packages', return_value=list(rows.values())).start()
        patch.object(sys, 'argv', ['coverage_report.py']).start()

    def run_report(self):
        with contextlib.redirect_stdout(io.StringIO()):
            report.main()

    def test_regression_fails_after_writing_report_and_explicit_update_passes(self):
        self.run_report()
        package = report.CRITICAL['lifecycle'].split('/lib/')[0]
        lcov = self.root / package / 'coverage/lcov.info'
        lcov.write_text(lcov.read_text().replace('method_channel_tracer.dart\nDA:1,1',
                                                 'method_channel_tracer.dart\nDA:1,0'))
        with self.assertRaisesRegex(SystemExit, 'below baseline: lifecycle'):
            self.run_report()
        summary = json.loads((self.output / 'summary.json').read_text())
        self.assertEqual(summary['critical']['lifecycle']['deltaPercentagePoints'], -50)
        self.assertTrue((self.output / 'index.html').exists())
        baseline = json.loads(self.baseline.read_text())
        baseline[report.CRITICAL['lifecycle']]['covered'] = 0
        self.baseline.write_text(json.dumps(baseline))
        self.run_report()

    def test_each_desktop_report_counts_shared_and_host_sources(self):
        for platform, host in report.DESKTOP_OS.items():
            with self.subTest(host=host), patch.object(sys, 'platform', platform):
                self.run_report()
                summary = json.loads((self.output / 'summary.json').read_text())
                self.assertNotIn(report.DESKTOP, summary['packages'])
                desktop = json.loads((self.output / f'desktop-{host}/summary.json').read_text())
                self.assertEqual(desktop['overall']['total'], 4)
                names = [Path(path).stem for path in desktop['files']]
                self.assertIn('shared', names)
                self.assertTrue(any(name.startswith(host + '_') for name in names))
