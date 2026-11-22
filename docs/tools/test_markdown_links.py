from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from check_markdown_links import check


class MarkdownLinksTest(unittest.TestCase):
    def test_rendered_links_headings_and_explicit_anchors(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp).resolve()
            source = root / "README.md"
            guide = root / "guide (1).md"
            guide.write_text('## Пример `API`\n## Пример API\n<a id="old"></a>')
            source.write_text(
                '[guide][ref] and [legacy](<guide (1).md#old>)\n\n'
                '[ref]: <guide (1).md#пример-api-1> "Guide"\n\n'
                '    # fake heading\n    [ignored](missing.md)\n\n'
                '`[ignored](missing.md)`\n\n[broken](#fake-heading)\n'
                '![image](missing.png)\n'
            )
            errors = check(root, [source])
            self.assertEqual(len(errors), 2, errors)
            self.assertIn('missing anchor: #fake-heading', errors[0])
            self.assertIn('missing target: missing.png', errors[1])


if __name__ == "__main__":
    unittest.main()
