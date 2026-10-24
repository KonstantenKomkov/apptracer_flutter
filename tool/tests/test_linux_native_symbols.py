import copy
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from symbolize_linux_native import crash_frame


class LinuxNativeSymbolsTests(unittest.TestCase):
    def test_requires_a_source_frame_in_the_crashing_thread(self):
        frame = {'module': 'runner', 'function': 'apptracer_native_crash()',
                 'file': '/repo/example/linux/runner/my_application.cc',
                 'line': 21, 'trust': 'cfi'}
        report = {'crash_info': {'type': 'SIGSEGV / SI_TKILL', 'crashing_thread': 0},
                  'threads': [{'frames': [frame]}, {'frames': []}]}
        self.assertEqual(crash_frame(report, 'runner'), frame)
        for change in ['wrong_thread', 'scanned_address', 'wrong_module', 'no_source']:
            bad = copy.deepcopy(report)
            item = bad['threads'][0]['frames'][0]
            if change == 'wrong_thread':
                bad['crash_info']['crashing_thread'] = 1
            elif change == 'scanned_address':
                item['trust'] = 'scan'
            elif change == 'wrong_module':
                item['module'] = 'another-runner'
            else:
                item['line'] = None
            with self.subTest(change=change), self.assertRaises(ValueError):
                crash_frame(bad, 'runner')


if __name__ == '__main__':
    unittest.main()
