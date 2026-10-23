from pathlib import Path
import struct
import sys
import unittest
import uuid

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from check_windows_symbols import breakpad_id, pdb_identity, require_identity, runner_frames


GUID = uuid.UUID('5128f31c-7efc-45f3-9a2a-510289ceef84')
IDENTITY = {'guid': str(GUID), 'age': 10}


def pdb_fixture():
    data = bytearray(6 * 512)
    data[:32] = b'Microsoft C/C++ MSF 7.00\r\n\x1aDS\0\0\0'
    struct.pack_into('<IIIIII', data, 32, 512, 1, 6, 24, 0, 2)
    struct.pack_into('<I', data, 2 * 512, 3)
    # An absent stream 0, then a fragmented Info stream in blocks 5 and 4.
    struct.pack_into('<IIIIII', data, 3 * 512, 2, 0xffffffff, 600, 5, 4, 0)
    struct.pack_into('<III', data, 5 * 512, 20000404, 123, 10)
    data[5 * 512 + 12:5 * 512 + 28] = GUID.bytes_le
    return data


class WindowsSymbolsTests(unittest.TestCase):
    def test_fragmented_info_stream_preserves_guid_byte_order_and_age(self):
        self.assertEqual(pdb_identity(pdb_fixture()), IDENTITY)
        self.assertEqual(breakpad_id(IDENTITY), '5128F31C7EFC45F39A2A510289CEEF84A')

    def test_truncated_or_out_of_bounds_pdb_is_rejected(self):
        invalid_block = pdb_fixture()
        struct.pack_into('<I', invalid_block, 3 * 512 + 12, 100)
        for data in [b'', pdb_fixture()[:-1], invalid_block]:
            with self.assertRaises(ValueError):
                pdb_identity(data)

    def test_foreign_guid_or_age_is_rejected(self):
        for identity in [{'guid': str(uuid.UUID(int=0)), 'age': 10},
                         {'guid': str(GUID), 'age': 11}]:
            with self.assertRaises(ValueError):
                require_identity(IDENTITY, identity)

    def test_source_frame_must_belong_to_crashing_thread_and_runner(self):
        frame = {'module': 'runner.exe', 'function': 'FlutterWindow::OnCreate',
                 'file': 'C:\\src\\flutter_window.cpp', 'line': 44, 'trust': 'scan'}
        report = {'crash_info': {'crashing_thread': 0},
                  'threads': [{'frames': [frame]}, {'frames': []}]}
        self.assertEqual(runner_frames(report, 'runner.exe'), [frame])
        with self.assertRaises(ValueError):
            runner_frames(report, 'other.exe')
        report['crash_info']['crashing_thread'] = 1
        with self.assertRaises(ValueError):
            runner_frames(report, 'runner.exe')


if __name__ == '__main__':
    unittest.main()
