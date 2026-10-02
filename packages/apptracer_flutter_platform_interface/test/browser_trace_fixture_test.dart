import 'package:apptracer_flutter_platform_interface/apptracer_flutter_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses an actual browser debug compiler error stack', () {
    try {
      throw StateError('browser trace fixture');
    } catch (_, stack) {
      final parsed = DartStackTrace.parse(stack);
      expect(parsed.raw, stack.toString());
      expect(parsed.symbolicFrames, isNotEmpty);
      expect(
          parsed.symbolicFrames.any((frame) =>
              frame.uri?.contains('browser_trace_fixture_test.dart') ?? false),
          isTrue);
    }
  }, skip: !kIsWeb);
}
