"""Host checks for SDK preparation; never load the vendor's target ELF."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile

TOOL = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(TOOL))
from prepare_aurora_sdk import extract, prepare, verify  # noqa: E402


class PreparationTests(unittest.TestCase):
    def test_wrong_archive_cannot_create_destination(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            archive = root / 'wrong.zip'
            archive.write_bytes(b'not the pinned SDK')
            target = root / 'sdk'
            with self.assertRaisesRegex(ValueError, 'archive checksum mismatch'):
                prepare(target, archive)
            self.assertFalse(target.exists())

    def test_existing_directory_is_never_overwritten(self):
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / 'sdk'
            target.mkdir()
            marker = target / 'user-file'
            marker.write_text('keep')
            with self.assertRaisesRegex(ValueError, 'checksum mismatch'):
                prepare(target)
            self.assertEqual(marker.read_text(), 'keep')

    def test_archive_traversal_is_rejected_before_any_extraction(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            archive = root / 'bad.zip'
            with zipfile.ZipFile(archive, 'w') as source:
                source.writestr('normal.txt', 'should not be written')
                source.writestr('../escaped.txt', 'must not escape')
            target = root / 'sdk'
            target.mkdir()
            with self.assertRaisesRegex(ValueError, 'unsafe SDK archive path'):
                extract(archive, target)
            self.assertEqual(list(target.iterdir()), [])
            self.assertFalse((root / 'escaped.txt').exists())

    def test_modified_header_and_symlink_are_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            header = root / 'tracer.h'
            expected = hashlib.sha256(b'original').hexdigest()
            lock = {'files': {'tracer.h': expected}}
            header.write_bytes(b'modified')
            with self.assertRaisesRegex(ValueError, 'checksum mismatch'):
                verify(root, lock)
            header.unlink()
            real = root / 'real.h'
            real.write_bytes(b'original')
            header.symlink_to(real)
            with self.assertRaisesRegex(ValueError, 'symlinks'):
                verify(root, lock)


class NativeProbeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.compiler = shutil.which('c++')
        if not cls.compiler or sys.platform == 'win32':
            raise unittest.SkipTest('requires a POSIX C++ compiler')
        cls.temp = tempfile.TemporaryDirectory()
        cls.root = Path(cls.temp.name)
        cls.probe = cls.root / 'probe'
        cls.flags = ['-ldl'] if sys.platform.startswith('linux') else []
        subprocess.run([cls.compiler, '-std=c++17', '-Wall', '-Wextra', '-Werror',
                        str(TOOL / 'aurora/sdk_probe.cc'), '-o', str(cls.probe),
                        *cls.flags], check=True)

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def test_missing_library_is_diagnostic(self):
        result = subprocess.run([str(self.probe), str(self.root / 'absent.so')],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)
        self.assertIn('could not be loaded', result.stderr)

    def test_loading_does_not_call_sdk_functions(self):
        # Every export aborts if called: success proves inspection is inert.
        symbols = ['tracer_init', 'tracer_set_platform_info2', 'tracer_set_key',
                   'tracer_set_userid', 'tracer_log', 'tracer_upload',
                   'tracer_disable_upload', 'tracer_aurora_collect_minidump_from_cachedir']
        for complete in [True, False]:
            source = self.root / ('full.cc' if complete else 'incomplete.cc')
            library = source.with_suffix('.so')
            source.write_text('#include <cstdlib>\n' + '\n'.join(
                'extern "C" void ' + name + '() { std::abort(); }'
                for name in (symbols if complete else symbols[:-1])))
            subprocess.run([self.compiler, '-shared', '-fPIC', str(source),
                            '-o', str(library)], check=True)
            result = subprocess.run([str(self.probe), str(library)],
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0 if complete else 1)
            if complete:
                payload = json.loads(result.stdout)
                self.assertFalse(payload['sdk_initialized'])
                self.assertFalse(payload['collection_contract_supported'])
            else:
                self.assertIn('missing an expected export', result.stderr)


class CMakeImportTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cmake = shutil.which('cmake')
        cls.sdk = os.environ.get('APPTRACER_AURORA_SDK_ROOT')
        if not cls.cmake or not cls.sdk:
            raise unittest.SkipTest('requires cmake and APPTRACER_AURORA_SDK_ROOT')

    def test_import_selects_target_abi_and_install_layout(self):
        for processor, arch in [('arm64', 'aarch64'), ('aarch64', 'aarch64'),
                                ('x86_64', 'x86_64'), ('riscv64', None)]:
            with self.subTest(processor=processor), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                # Configure only: this is explicitly not an Aurora toolchain.
                (root / 'CMakeLists.txt').write_text(
                    'cmake_minimum_required(VERSION 3.14)\nproject(check NONE)\n'
                    'set(CMAKE_SYSTEM_NAME Linux)\n'
                    f'set(CMAKE_SYSTEM_PROCESSOR {processor})\n'
                    f'include("{TOOL / "aurora/TracerNative.cmake"}")\n'
                    f'apptracer_import_aurora_sdk("{self.sdk}")\n'
                    'apptracer_install_aurora_sdk("share/probe/lib")\n')
                result = subprocess.run([self.cmake, '-S', str(root), '-B', str(root / 'build'),
                                         '-DCMAKE_INSTALL_PREFIX=' + str(root / 'install')],
                                        capture_output=True, text=True)
                if arch is None:
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn('Unaudited Aurora target ABI', result.stderr)
                    continue
                self.assertEqual(result.returncode, 0, result.stderr)
                subprocess.run([self.cmake, '--install', str(root / 'build')],
                               check=True, capture_output=True)
                installed = root / 'install/share/probe/lib/libtracernative.so'
                original = Path(self.sdk) / 'aurora/lib' / arch / 'libtracernative.so'
                self.assertEqual(installed.read_bytes(), original.read_bytes())


if __name__ == '__main__':
    unittest.main()
