import struct
import sys
from pathlib import Path
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from check_linux_runtime import inspect_linux_dump
from test_windows_native import dump_fixture


BUILD_ID = '0123456789abcdef0123456789abcdef01234567'


def linux_dump():
    data = bytearray(dump_fixture())
    name = '/tmp/probe/apptracer_desktop_example'.encode('utf-16-le')
    struct.pack_into('<I', data, 336, len(name))
    data[340:340 + len(name)] = name
    cv = b'LEpB' + bytes.fromhex(BUILD_ID)
    struct.pack_into('<II', data, 60 + 76, len(cv), 440)
    data[440:440 + len(cv)] = cv
    struct.pack_into('<I', data, 168 + 8, 11)
    return bytes(data)


class LinuxNativeParsingTests(unittest.TestCase):
    @patch('check_linux_runtime.build_id', return_value=BUILD_ID)
    def test_linux_signal_and_elf_identity(self, unused):
        report = inspect_linux_dump(linux_dump(), Path('/bundle/apptracer_desktop_example'))
        self.assertEqual(report['exception'], 11)
        self.assertEqual(report['runner']['build_id'], BUILD_ID)

    @patch('check_linux_runtime.build_id', return_value='another-build')
    def test_foreign_elf_and_truncated_dump_are_rejected(self, unused):
        for data in [linux_dump(), linux_dump()[:100]]:
            with self.assertRaises(ValueError):
                inspect_linux_dump(data, Path('/bundle/apptracer_desktop_example'))


if __name__ == '__main__':
    unittest.main()
