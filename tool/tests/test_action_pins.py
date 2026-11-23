from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import check_action_pins as pins

SHA = '3d3c42e5aac5ba805825da76410c181273ba90b1'


class ActionPinsTest(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.workflows = self.root / '.github/workflows'
        self.workflows.mkdir(parents=True)

    def write(self, content, name='test.yml'):
        path = self.workflows / name
        path.write_text(content)
        return path

    def test_full_sha_and_local_reusable_workflow_pass(self):
        path = self.write(
            f'jobs:\n'
            f'  test:\n'
            f'    steps:\n'
            f'      - uses: actions/checkout@{SHA} # v7\n'
            f'  local:\n'
            f'    uses: ./.github/workflows/reusable.yml\n'
        )
        self.assertEqual(pins.check_workflow(path), [])

    def test_tag_branch_short_sha_and_missing_comment_fail(self):
        cases = {
            'tag': 'actions/checkout@v7 # v7',
            'branch': 'actions/checkout@main # main',
            'short SHA': f'actions/checkout@{SHA[:7]} # v7',
            'missing comment': f'actions/checkout@{SHA}',
        }
        for label, value in cases.items():
            with self.subTest(label=label):
                path = self.write(f'steps:\n  - uses: {value}\n')
                self.assertEqual(len(pins.check_workflow(path)), 1)

    def test_multiline_external_and_local_uses(self):
        path = self.write(
            f'jobs:\n'
            f'  external:\n'
            f'    steps:\n'
            f'      - uses: >- # v7\n'
            f'          actions/checkout@{SHA}\n'
            f'  local:\n'
            f'    uses: >-\n'
            f'      ./.github/workflows/reusable.yml\n'
        )
        self.assertEqual(pins.check_workflow(path), [])

    def test_multiline_tag_fails(self):
        path = self.write(
            'steps:\n'
            '  - uses: >- # v7\n'
            '      actions/checkout@v7\n'
        )
        self.assertEqual(len(pins.check_workflow(path)), 1)

    def test_directory_checks_yml_and_yaml_only(self):
        self.write(f'steps:\n  - uses: actions/checkout@{SHA} # v7\n')
        (self.workflows / 'nested').mkdir()
        (self.workflows / 'nested/test.yaml').write_text(
            'steps:\n  - uses: actions/checkout@v7\n'
        )
        (self.workflows / 'ignored.txt').write_text('uses: actions/checkout@v7\n')
        paths, errors = pins.check_workflows(self.workflows)
        self.assertEqual([path.suffix for path in paths], ['.yaml', '.yml'])
        self.assertEqual(len(errors), 1)


if __name__ == '__main__':
    unittest.main()
