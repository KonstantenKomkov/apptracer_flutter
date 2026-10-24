import 'package:apptracer_flutter/src/error_normalizer.dart';
import 'package:apptracer_flutter_platform_interface/apptracer_flutter_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

class RenamedFlutterError extends FlutterError {
  RenamedFlutterError() : super.fromParts([ErrorSummary('framework failure')]);

  @override
  Type get runtimeType => String;
}

void main() {
  test('FlutterError type survives renamed runtimeType', () {
    final event = ErrorNormalizer.fromFlutterError(
      FlutterErrorDetails(exception: RenamedFlutterError()),
      severity: TracerSeverity.error,
      fatal: false,
    );
    expect(event.exceptionType, 'FlutterError');
    expect(event.message, 'framework failure');
  });

  test('framework details retain the actual non-FlutterError type', () {
    final event = ErrorNormalizer.fromFlutterError(
      FlutterErrorDetails(exception: StateError('failure')),
      severity: TracerSeverity.error,
      fatal: false,
    );
    expect(event.exceptionType, 'StateError');
  });
}
