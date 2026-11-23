import contextlib
from importlib.util import find_spec
from io import StringIO
from pathlib import Path
import sys
import tempfile
from textwrap import indent
import unittest
from unittest.mock import patch

# Platform acceptance jobs also discover tool/tests with their system Python.
if find_spec('yaml') is None:
    raise unittest.SkipTest('Install tool/requirements-action-pins.txt to run action pin tests')

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import check_action_pins as pins

SHA = '3d3c42e5aac5ba805825da76410c181273ba90b1'
ACTION = f'actions/checkout@{SHA}'


class ActionPinsTest(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.workflows = Path(directory.name) / '.github/workflows'
        self.workflows.mkdir(parents=True)

    def write(self, content, name='test.yml'):
        path = self.workflows / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding='utf-8')
        return path

    def steps(self, content, name='test.yml'):
        return self.write('jobs:\n  build:\n    runs-on: ubuntu-latest\n    steps:\n'
                          + indent(content, '      ') + '\n', name)

    def test_pinned_step_and_reusable_workflows(self):
        path = self.write(
            'jobs:\n'
            '  remote:\n'
            f'    uses: example/shared/.github/workflows/build.yml@{SHA} # v2.1.0\n'
            '  local:\n'
            '    uses: >-\n'
            '      ./.github/workflows/reusable.yml\n'
            '  build:\n'
            '    steps:\n'
            f'      - uses: "{ACTION}" # v7\n'
            '      - uses: ./.github/actions/build\n'
        )
        self.assertEqual(pins.check_workflow(path), [])

    def test_mutable_or_incomplete_refs_report_line_and_value(self):
        for ref in ['v7', 'main', SHA[:7], SHA + '0', 'g' * 40]:
            with self.subTest(ref=ref):
                path = self.steps(f'- "uses": actions/checkout@{ref} # v7')
                error, = pins.check_workflow(path)
                self.assertIn(f'{path}:5:', error)
                self.assertIn('40-character commit SHA', error)
                self.assertIn(f'actions/checkout@{ref}', error)

    def test_multiline_scalar_styles_and_sibling_keys(self):
        for value in [f"'{ACTION}' # v7", f'\n    {ACTION} # v7',
                      f'# v7\n    "{ACTION}"', f'>- # v7\n    {ACTION}',
                      f'&checkout\n    >- # v7\n      {ACTION}',
                      f'|2- # release-2024.11\n    {ACTION}']:
            with self.subTest(value=value):
                path = self.steps(f'- uses: {value}\n  with:\n    fetch-depth: 1')
                self.assertEqual(pins.check_workflow(path), [])

    def test_folded_tag_and_scalar_content_are_checked_as_yaml_values(self):
        for value in ['>- # v7\n    actions/checkout@v7',
                      f"'{ACTION} # v7'", f'{ACTION}#v7',
                      f'|-\n    {ACTION} # v7', f'|- # v7\n    {ACTION}\n    extra']:
            with self.subTest(value=value):
                path = self.steps(f'- uses: {value}')
                error, = pins.check_workflow(path)
                self.assertIn('40-character commit SHA', error)

    def test_version_comment_belongs_to_reference(self):
        for suffix in ['', ' #', ' #  ', '\n  # v7', '\n  with: {} # v7']:
            with self.subTest(suffix=suffix):
                path = self.steps(f'- uses: {ACTION}{suffix}')
                error, = pins.check_workflow(path)
                self.assertIn(f'{path}:5:', error)
                self.assertIn('version comment', error)

    def test_flow_style_steps_and_job_calls(self):
        path = self.write(
            'jobs:\n'
            '  build:\n'
            f'    steps: [{{uses: "{ACTION}", with: {{fetch-depth: 1}}}}] # v7\n'
            '  remote: {"uses": example/shared/.github/workflows/build.yml@main}\n'
        )
        error, = pins.check_workflow(path)
        self.assertIn(f'{path}:4:', error)
        self.assertIn('build.yml@main', error)

    def test_script_inputs_and_other_uses_keys_are_ignored(self):
        path = self.steps(
            '- run: |\n'
            '    uses: some/script-text\n'
            f'- uses: {ACTION} # v7\n'
            '  with:\n'
            '    uses: some/input\n'
            '  env:\n'
            '    USES: some/variable'
        )
        self.assertEqual(pins.check_workflow(path), [])

    def test_invalid_yaml_and_non_scalar_uses_report_file_and_line(self):
        for step, message in [('- uses: [}', 'invalid YAML'), ('- uses: {}', 'scalar')]:
            with self.subTest(step=step):
                path = self.steps(step)
                error, = pins.check_workflow(path)
                self.assertIn(f'{path}:5:', error)
                self.assertIn(message, error)

    def test_directory_and_cli_report_all_failing_files(self):
        self.assertTrue(pins.check_workflows(self.workflows)[1])
        first = self.steps('- uses: actions/checkout@main', 'ordinary.yml')
        second = self.steps('- uses: actions/checkout@v7', 'nested/other.yaml')
        self.steps('- uses: actions/checkout@v7', 'ignored.txt')
        paths, errors = pins.check_workflows(self.workflows)
        self.assertEqual(paths, sorted([first, second]))
        self.assertEqual(len(errors), 2)
        with patch.object(pins, 'WORKFLOWS', self.workflows):
            with contextlib.redirect_stderr(StringIO()) as stderr:
                self.assertEqual(pins.main(), 1)
        self.assertEqual(stderr.getvalue().splitlines(), errors)


if __name__ == '__main__':
    unittest.main()
