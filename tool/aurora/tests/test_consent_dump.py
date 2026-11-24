import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import unittest

PLUGIN = (Path(__file__).resolve().parents[3] /
          'aurora/apptracer_flutter_aurora/aurora')


class ConsentDumpTests(unittest.TestCase):
    def test_only_exact_mapping_in_complete_linux_maps_stream_authorizes_replay(self):
        compiler = shutil.which(os.environ.get('CXX', 'c++'))
        if not compiler:
            self.skipTest('C++ compiler required')
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            driver = directory / 'check.cc'
            driver.write_text(
                '#include "minidump.h"\n'
                'int main(int argc, char** argv) {\n'
                '  return apptracer::containsSessionMapping(argv[1], argv[2]) ? 0 : 1;\n'
                '}\n')
            exe = directory / 'check'
            subprocess.run([compiler, '-std=c++17', '-I', str(PLUGIN), str(driver),
                            str(PLUGIN / 'minidump.cc'), '-o', str(exe)], check=True)
            path = '/private data/consent-0123'
            maps = f'1000-2000 r--s 00000000 fd:01 44 {path}\n'.encode()
            header = b'MDMP' + struct.pack('<III', 0xa793, 1, 32) + bytes(16)
            entry = struct.pack('<III', 0x47670009, len(maps), 44)
            valid = header + entry + maps
            for label, data, marker, expected in [
                ('valid', valid, path, True),
                ('different consent', valid, path[:-1], False),
                ('empty', b'', path, False),
                ('truncated', valid[:-1], path, False),
                ('non-maps bytes', header + bytes(12) + maps, path, False),
                ('invalid offset', header + struct.pack('<III', 0x47670009, 32, 0xfffffff0) + maps, path, False),
            ]:
                with self.subTest(label):
                    dump = directory / 'minidump'
                    dump.write_bytes(data)
                    result = subprocess.run([str(exe), str(dump), marker])
                    self.assertEqual(result.returncode, 0 if expected else 1)
