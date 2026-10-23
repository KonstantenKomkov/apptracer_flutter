import gzip
import io
import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from check_macos_desktop import envelope_events, read_http_body


class DesktopReceiverTests(unittest.TestCase):
    def test_chunked_compressed_dart_envelope_with_trailers(self):
        event = json.dumps({'message': 'Unicode: \u041f\u0440\u0438\u0432\u0435\u0442'}).encode()
        envelope = b'{}\n' + json.dumps({'type': 'event', 'length': len(event)}).encode() + b'\n' + event
        compressed = gzip.compress(envelope)
        parts = [compressed[:7], compressed[7:]]
        wire = b''.join(('%x;extension=yes\r\n' % len(part)).encode() + part + b'\r\n'
                        for part in parts) + b'0\r\nX-Test: value\r\n\r\n'
        body = read_http_body(io.BytesIO(wire), {'Transfer-Encoding': 'chunked'})
        self.assertEqual(list(envelope_events(gzip.decompress(body))), [('event', json.loads(event))])

    def test_fixed_length_cocoa_upload_still_works(self):
        self.assertEqual(read_http_body(io.BytesIO(b'abc'), {'Content-Length': '3'}), b'abc')

    def test_truncated_and_oversized_uploads_fail(self):
        for body, headers in [
            (b'3\r\nab', {'Transfer-Encoding': 'chunked'}),
            (b'3\r\nabc\r\n0\r\n', {'Transfer-Encoding': 'chunked'}),
            (b'ffffffff\r\n', {'Transfer-Encoding': 'chunked'}),
            (b'a', {'Content-Length': '2'}),
        ]:
            with self.subTest(body=body), self.assertRaises(ValueError):
                read_http_body(io.BytesIO(body), headers)


if __name__ == '__main__':
    unittest.main()
