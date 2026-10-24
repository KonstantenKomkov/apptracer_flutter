from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from prepare_linux_dart_runtime_symbols import parse_breakpad


class DartRuntimeMapTests(unittest.TestCase):
    identity = 'fed6889c5704bdde60d6ce8804d49225'
    text = ('MODULE Linux x86_64 9C88D6FE0457DEBD60D6CE8804D492250 libapp.so\n'
            'FILE 9 /app with spaces/main.dart\n'
            'FUNC m 230 20 0 perform action\n'
            '234 4 73 9\n'
            'INLINE_ORIGIN 0 other\n'
            'INLINE 0 72 9 0 238 4\n'
            '238 4 74 9\n'
            'STACK CFI INIT 230 20 .cfa: $rsp 8 +\n')

    def test_preserves_ranges_names_and_file_numbers(self):
        result = parse_breakpad(self.text, self.identity)
        self.assertEqual(result['files'], ['/app with spaces/main.dart'])
        self.assertEqual(result['functions'], [[0x230, 0x20, 'perform action']])
        self.assertEqual(result['lines'], [[0x234, 4, 0, 73], [0x238, 4, 0, 74]])

    def test_rejects_wrong_module_and_missing_source(self):
        for text in [self.text.replace('libapp.so', 'other.so'),
                     self.text.replace('9C88D6FE', '00000000'),
                     self.text.split('FILE')[0]]:
            with self.assertRaises(ValueError):
                parse_breakpad(text, self.identity)
