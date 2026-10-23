import struct
import sys
from pathlib import Path
import unittest
import uuid

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from check_windows_native import codeview, inspect_dump, multipart_dumps, pe_identity


GUID = uuid.UUID('e5f09782-393f-4ac5-a388-7c3f5c619a6b')
CV = b'RSDS' + GUID.bytes_le + struct.pack('<I', 3) + b'runner.pdb\0'
IDENTITY = {'guid': str(GUID), 'age': 3}


def dump_fixture():
    data = bytearray(512)
    data[:4] = b'MDMP'
    struct.pack_into('<III', data, 4, 0xa793, 2, 32)
    struct.pack_into('<III', data, 32, 4, 112, 56)
    struct.pack_into('<III', data, 44, 6, 168, 168)
    struct.pack_into('<I', data, 56, 1)
    struct.pack_into('<I', data, 60 + 20, 336)
    struct.pack_into('<II', data, 60 + 76, len(CV), 440)
    struct.pack_into('<I', data, 168 + 8, 0xc0000005)
    name = 'C:\\test\\apptracer_desktop_example.exe'.encode('utf-16-le')
    struct.pack_into('<I', data, 336, len(name))
    data[340:340+len(name)] = name
    data[440:440+len(CV)] = CV
    return bytes(data)


class WindowsNativeParsingTests(unittest.TestCase):
    def test_native_dump_contains_the_runner_and_expected_exception(self):
        report = inspect_dump(dump_fixture(), 'apptracer_desktop_example.exe')
        self.assertEqual(report['runner']['codeview'], IDENTITY)
        self.assertEqual(report['exception_code'], '0xc0000005')
        self.assertEqual(codeview(CV), IDENTITY)

    def test_truncated_dump_and_absent_runner_are_rejected(self):
        for data, name in [(dump_fixture()[:100], 'apptracer_desktop_example.exe'),
                           (dump_fixture(), 'other.exe')]:
            with self.assertRaises(ValueError):
                inspect_dump(data, name)

    def test_pe_identity_uses_debug_directory_file_pointer(self):
        data = bytearray(1024)
        data[:2] = b'MZ'
        struct.pack_into('<I', data, 0x3c, 0x80)
        data[0x80:0x84] = b'PE\0\0'
        struct.pack_into('<H', data, 0x86, 1)
        struct.pack_into('<H', data, 0x94, 240)
        struct.pack_into('<H', data, 0x98, 0x20b)
        struct.pack_into('<II', data, 0x98 + 112 + 48, 0x1000, 28)
        struct.pack_into('<IIII', data, 0x98 + 240 + 8, 512, 0x1000, 512, 512)
        struct.pack_into('<I', data, 512 + 12, 2)
        struct.pack_into('<I', data, 512 + 16, len(CV))
        struct.pack_into('<I', data, 512 + 24, 560)
        data[560:560+len(CV)] = CV
        self.assertEqual(pe_identity(data), IDENTITY)

    def test_multipart_preserves_binary_bytes_and_requires_one_dump(self):
        payload = b'MDMP\x00\xff\r\n'
        body = (b'--test\r\nContent-Disposition: form-data; name="upload_file_minidump"; filename="dump.dmp"\r\n'
                b'Content-Type: application/octet-stream\r\n\r\n' + payload + b'\r\n--test--\r\n')
        self.assertEqual(multipart_dumps('multipart/form-data; boundary=test', body), payload)
        with self.assertRaises(ValueError):
            multipart_dumps('text/plain', payload)


if __name__ == '__main__':
    unittest.main()
