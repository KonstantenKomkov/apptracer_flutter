from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from symbolize_macos_dart import validate_stack


BUILD_ID = '36ee816c8bd8e9f1c2167a45cabf3676'
IDS = {'arm64': BUILD_ID}
RAW = """*** *** *** *** *** *** *** *** *** *** *** *** *** *** *** ***
pid: 26590, tid: 8624095104, name io.flutter.platform
os: macos arch: arm64 comp: no sim: no
build_id: '36ee816c8bd8e9f1c2167a45cabf3676'
isolate_dso_base: 106bec000, vm_dso_base: 0
isolate_instructions: 106bf0000, vm_instructions: 0
    #00 abs 0000000106ec3c7b virt 00000000002d7c7b _kDartSnapshotText+0x2d3c7b
"""


class MacOSDartSymbolsTests(unittest.TestCase):
    def test_captured_snapshot_text_uses_virtual_pc_without_rebasing_twice(self):
        arch, identity, frames = validate_stack(RAW, IDS, IDS)
        self.assertEqual((arch, identity), ('arm64', BUILD_ID))
        self.assertEqual(frames, [{'index': 0, 'virtual_pc': '0x2d7c7b'}])

    def test_other_build_or_architecture_is_rejected_before_decoding(self):
        for symbols, image in [({}, IDS), (IDS, {}),
                               ({'arm64': '0' * 32}, IDS),
                               (IDS, {'arm64': '0' * 32}),
                               ({'x86_64': BUILD_ID}, IDS)]:
            with self.subTest(symbols=symbols, image=image):
                with self.assertRaisesRegex(ValueError, 'do not match'):
                    validate_stack(RAW, symbols, image)

    def test_missing_identity_wrong_platform_and_broken_addresses_fail_closed(self):
        for raw in [RAW.replace('build_id:', 'lost_id:'),
                    RAW.replace('os: macos', 'os: android'),
                    RAW.replace('106bec000,', '106bed000,'),
                    RAW.replace(' virt 00000000002d7c7b', ''),
                    RAW[:RAW.index('    #00')]]:
            with self.subTest(raw=raw):
                with self.assertRaises(ValueError):
                    validate_stack(raw, IDS, IDS)


if __name__ == '__main__':
    unittest.main()
