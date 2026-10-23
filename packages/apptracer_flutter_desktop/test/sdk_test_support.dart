import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class NativeSdkProbe {
  final calls = <MethodCall>[];
  Future<Object?> Function(MethodCall)? onCall;

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('dev.fluttercommunity.plus/package_info'),
            (_) async => <String, dynamic>{
                  'appName': 'SDK test',
                  'packageName': 'dev.apptracer.test',
                  'version': '1.0.0',
                  'buildNumber': '1',
                  'buildSignature': '',
                });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('sentry_flutter'),
            (call) async {
      calls.add(call);
      if (onCall != null) return onCall!(call);
      return null;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('apptracer_flutter_desktop/lifecycle'),
            (call) async {
      calls.add(call);
      if (onCall != null) {
        final result = await onCall!(call);
        if (result != null) return result;
      }
      return <String, Object?>{
        'state': call.method == 'initNativeSdk' ? 'enabled' : 'restartRequired',
        if (call.method == 'clearNativeSdk')
          'reason': 'macos_cleared_restart_required',
      };
    });
  }

  List<Map<String, dynamic>> get events =>
      calls.where((call) => call.method == 'captureEnvelope').map((call) {
        final args = call.arguments as List<dynamic>;
        final lines = utf8.decode(args[0] as List<int>).split('\n');
        expect(jsonDecode(lines[1]), containsPair('type', 'event'));
        return jsonDecode(lines[2]) as Map<String, dynamic>;
      }).toList();
}
