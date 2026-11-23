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
        self.desktop_lcov = self.root / report.DESKTOP / 'coverage/lcov.info'
        self.lifecycle = report.DESKTOP_CRITICAL['desktop_lifecycle']
        self.baseline = self.root / 'tool/coverage_baseline.json'
        self.baseline.parent.mkdir()
        self.baseline.write_text(json.dumps({
            path: {'covered': 1, 'total': 2} for path in report.CRITICAL.values()
        }))
        self.desktop_baseline = self.root / 'tool/desktop_coverage_baseline.json'
        self.desktop_baseline.write_text(json.dumps({
            host: {self.lifecycle: {'covered': 1, 'total': 2}}
            for host in report.DESKTOP_OS.values()
        }))
        paths = list(report.CRITICAL.values()) + [
            f'{report.DESKTOP}/lib/src/{name}.dart'
            for name in ('shared', 'sentry_desktop_tracer', 'linux_storage',
                         'windows_storage', 'macos_lifecycle')
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

    def run_report(self, *args):
        with patch.object(sys, 'argv', ['coverage_report.py', *args]), \
                contextlib.redirect_stdout(io.StringIO()):
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
                self.assertEqual(set(summary['critical']), set(report.CRITICAL))
                desktop = json.loads((self.output / f'desktop-{host}/summary.json').read_text())
                self.assertEqual(desktop['overall']['total'], 6)
                self.assertIn('desktop_lifecycle', desktop['critical'])
                platform_files = {'linux': 'linux_storage', 'windows': 'windows_storage',
                                  'macos': 'macos_lifecycle'}
                self.assertEqual({Path(path).stem for path in desktop['files']},
                                 {'shared', 'sentry_desktop_tracer', platform_files[host]})
                self.assertEqual({Path(path).stem for path in desktop['excludedPlatformFiles']},
                                 {name for os, name in platform_files.items() if os != host})
                self.assertEqual(desktop['unmeasuredLibraryFiles'], [])

    def test_desktop_regression_fails_and_intentional_update_passes(self):
        self.desktop_lcov.write_text(self.desktop_lcov.read_text().replace(
            'sentry_desktop_tracer.dart\nDA:1,1',
            'sentry_desktop_tracer.dart\nDA:1,0'))
        baseline = json.loads(self.desktop_baseline.read_text())
        for platform, host in report.DESKTOP_OS.items():
            with self.subTest(host=host), patch.object(sys, 'platform', platform):
                for args in (('--desktop-only',), ()):
                    with self.subTest(args=args), self.assertRaisesRegex(SystemExit, 'desktop_lifecycle'):
                        self.run_report(*args)
                summary = json.loads((self.output / f'desktop-{host}/summary.json').read_text())
                self.assertEqual(summary['critical']['desktop_lifecycle']['deltaPercentagePoints'], -50)
                baseline[host][self.lifecycle]['covered'] = 0
                self.desktop_baseline.write_text(json.dumps(baseline))
                self.run_report('--desktop-only')
                self.run_report()

    def test_normal_run_reports_simultaneous_regressions(self):
        self.desktop_lcov.write_text(self.desktop_lcov.read_text().replace('DA:1,1', 'DA:1,0'))
        baseline = json.loads(self.baseline.read_text())
        baseline[report.CRITICAL['http_transport']]['covered'] = 2
        self.baseline.write_text(json.dumps(baseline))
        with self.assertRaisesRegex(SystemExit, 'below baseline: desktop_lifecycle, http_transport'):
            self.run_report()
        summary = json.loads((self.output / 'summary.json').read_text())
        self.assertEqual(summary['critical']['http_transport']['deltaPercentagePoints'], -50)

    def test_lcov_paths_merge_only_this_packages_production_lines(self):
        relative = self.lifecycle.split(report.DESKTOP + '/')[1]
        sources = [relative, './' + relative, self.lifecycle.replace('/', '\\'),
                   str(self.root / self.lifecycle)]
        ignored = [str(self.root / report.CRITICAL['parser']), 'lib/../test/fixture.dart',
                   'lib/src/generated.g.dart']
        self.desktop_lcov.write_text(''.join(
            f'SF:{source}\nDA:1,1\nend_of_record\n' for source in sources + ignored))
        self.run_report('--desktop-only')
        directory = self.output / ('desktop-' + report.DESKTOP_OS[sys.platform])
        self.assertIn(f'SF:{self.lifecycle}\nDA:1,4\n', (directory / 'lcov.info').read_text())
        summary = json.loads((directory / 'summary.json').read_text())
        self.assertEqual(summary['files'], {self.lifecycle: {'covered': 1, 'total': 1}})

    def test_missing_empty_and_unmeasured_desktop_input(self):
        self.desktop_lcov.unlink()
        for contents, message in [(None, 'Missing or empty'), ('', 'Missing or empty'),
                                  ('SF:test/only.dart\nDA:1,1', 'No production lines'),
                                  ('SF:lib/src/shared.dart\nDA:1,1', 'Missing critical file')]:
            if contents is not None:
                self.desktop_lcov.write_text(contents)
            for args in ((), ('--desktop-only',)):
                with self.subTest(contents=contents, args=args), self.assertRaisesRegex(SystemExit, message):
                    self.run_report(*args)

    def test_desktop_only_runs_without_common_inputs(self):
        self.baseline.unlink()
        (self.root / 'packages/apptracer_flutter/coverage/lcov.info').unlink()
        self.run_report('--desktop-only')
        self.assertFalse((self.output / 'summary.json').exists())
        with self.assertRaisesRegex(SystemExit, 'Missing or empty coverage input'):
            self.run_report()

    def test_unsupported_host_fails_explicitly(self):
        with patch.object(sys, 'platform', 'freebsd'):
            with self.assertRaisesRegex(SystemExit, 'Unsupported desktop coverage platform: freebsd'):
                self.run_report('--desktop-only')

    def test_missing_or_invalid_critical_baseline_fails(self):
        host = report.DESKTOP_OS[sys.platform]
        for entries, message in [({}, 'Missing critical coverage baseline'),
                                 ({self.lifecycle: {'covered': 0, 'total': 0}}, 'Invalid coverage baseline')]:
            self.desktop_baseline.write_text(json.dumps({host: entries}))
            with self.subTest(entries=entries), self.assertRaisesRegex(SystemExit, message):
                self.run_report('--desktop-only')

    def test_missing_host_baseline_fails_explicitly(self):
        baseline = json.loads(self.desktop_baseline.read_text())
        del baseline['windows']
        self.desktop_baseline.write_text(json.dumps(baseline))
        with patch.object(sys, 'platform', 'win32'):
            with self.assertRaisesRegex(SystemExit, 'host: windows'):
                self.run_report()
