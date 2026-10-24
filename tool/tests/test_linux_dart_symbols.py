import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from symbolize_linux_dart import validate_stack


RAW = "os: linux arch: x64 comp: no sim: no\nbuild_id: 'abc123'\n" \
      "isolate_dso_base: 7c657c364000\n" \
      "    #00 abs 00007c657c7cb716 virt 0000000000467716 _kDartSnapshotText+0x307716\n"


class LinuxDartSymbolsTests(unittest.TestCase):
    def test_virtual_pc_is_not_rebased_twice(self):
        self.assertEqual(validate_stack(RAW, 'abc123'), ['0x0000000000467716'])

    def test_foreign_build_platform_and_missing_frames_fail(self):
        for raw, identity in [(RAW, 'other'), (RAW.replace('linux', 'macos'), 'abc123'),
                              (RAW.replace('x64', 'arm64'), 'abc123'),
                              (RAW.split('    #00')[0], 'abc123')]:
            with self.assertRaises(ValueError):
                validate_stack(raw, identity)


if __name__ == '__main__':
    unittest.main()
