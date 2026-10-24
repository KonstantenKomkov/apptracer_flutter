import 'dart:async';
import 'dart:io';

import 'package:apptracer_flutter/apptracer_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'lifecycle_probe.dart';
import 'probe_configuration.dart';

const _native = MethodChannel('apptracer_desktop_example');

Future<void> main() async {
  // Native/Dart plugin registration selects the adapter. Merely loading the
  // plugin does not initialize Sentry. Runtime env is useful when launching .app
  // outside an IDE; plugin tokens are never read by this application.
  final dsn = probeDsn;
  final scenario = Platform.environment['TRACER_SCENARIO'] ?? '';
  final runId = Platform.environment['TRACER_RUN_ID'] ?? 'manual';
  await Tracer.initialize(
    options: TracerOptions(
      dsn: dsn,
      release: '1.0.0',
      dist: '1',
      environment: 'desktop-acceptance',
      preservePreviousReports:
          Platform.environment['TRACER_PRESERVE_REPORTS'] != 'false',
      nativeInitialization: scenario == 'deferred' || scenario == 'lifecycle'
          ? TracerNativeInitialization.deferred
          : TracerNativeInitialization.automatic,
      isCollectionEnabled: scenario != 'disabled',
      initialCustomKeys: {'probe_run': runId},
    ),
    appRunner: () {
      runApp(const DesktopProbeApp());
      if (scenario.isNotEmpty) {
        unawaited(_runScenario(scenario));
      }
    },
  );
}

Future<void> _handled() async {
  try {
    throw StateError('desktop handled probe');
  } catch (error, stack) {
    await Tracer.recordError(error, stack, issueKey: 'desktop-handled-probe');
  }
}

void _flutterError() {
  FlutterError.reportError(
    FlutterErrorDetails(
      exception: FlutterError('desktop FlutterError probe'),
      stack: StackTrace.current,
      library: 'desktop acceptance',
    ),
  );
}

void _asyncError() {
  unawaited(
    Future<void>.delayed(const Duration(milliseconds: 10), () {
      throw StateError('desktop async probe');
    }),
  );
}

Future<void> _runScenario(String scenario) async {
  final state = await Tracer.getCollectionState();
  final ready = 'APPTRACER_READY enabled=${Tracer.isEnabled} '
      'backend=${TracerPlatform.instance.backendName} state=${state.state.name}';
  debugPrint(ready);
  // A Windows GUI process need not have a console or inherited stdout.
  // Only opt-in probes write this status file; it contains no credentials.
  final readyPath = Platform.environment['TRACER_PROBE_READY_FILE'];
  if (readyPath != null) await File(readyPath).writeAsString(ready);
  if (scenario == 'lifecycle') {
    await runLifecycleProbe();
  } else if (scenario == 'smoke') {
    await Tracer.setUserId('desktop-test-user');
    Tracer.addBreadcrumb(
      TracerBreadcrumb(
        message: 'desktop probe started',
        category: 'probe',
        data: const {'source': 'release-app'},
      ),
    );
    await _handled();
    _flutterError();
    _asyncError();
  } else if (scenario == 'native-crash') {
    // This scenario is opt-in, launched in a dedicated example process.
    Tracer.addBreadcrumb(TracerBreadcrumb(message: 'before native crash'));
    await Future<void>.delayed(const Duration(seconds: 1));
    await _native.invokeMethod<void>('nativeCrash');
  }
}

/// Controls for inspecting desktop SDK behavior without production data.
class DesktopProbeApp extends StatefulWidget {
  /// Creates the acceptance example.
  const DesktopProbeApp({super.key});

  @override
  State<DesktopProbeApp> createState() => _DesktopProbeAppState();
}

class _DesktopProbeAppState extends State<DesktopProbeApp> {
  String _status = 'Use the controls to inspect collection state.';

  Future<void> _act(Future<void> Function() action) async {
    await action();
    final result = await Tracer.getCollectionState();
    if (!mounted) return;
    setState(() => _status = '${result.state.name}: ${result.reason ?? "OK"}');
  }

  Future<void> _confirmNativeCrash(BuildContext context) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Terminate the example?'),
        content: const Text(
          'This creates a native crash report. Restart the example to test delivery.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Crash'),
          ),
        ],
      ),
    );
    if (accepted == true) await _native.invokeMethod<void>('nativeCrash');
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Tracer desktop probe',
        home: Builder(
          builder: (context) => Scaffold(
            appBar: AppBar(title: const Text('Tracer · desktop acceptance')),
            body: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Backend: ${TracerPlatform.instance.backendName}'),
                  Text('Collection: ${Tracer.isEnabled ? "enabled" : "off"}'),
                  const SizedBox(height: 12),
                  Text(
                    Platform.isWindows
                        ? 'Windows: stop cancels delivery; clear deletes the adapter queue. '
                            'Starting again requires a process restart.'
                        : Platform.isLinux
                            ? 'Linux: restarting collection requires a process restart. '
                                'Stop cancels delivery; clear deletes the adapter queue.'
                            : 'macOS: stop cancels delivery; clear deletes the adapter queue. '
                                'Starting again requires a process restart.',
                  ),
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton(
                        onPressed: () => _act(_handled),
                        child: const Text('Handled Dart error'),
                      ),
                      OutlinedButton(
                        onPressed: _flutterError,
                        child: const Text('FlutterError'),
                      ),
                      OutlinedButton(
                        onPressed: _asyncError,
                        child: const Text('Async error'),
                      ),
                      OutlinedButton(
                        onPressed: () => _confirmNativeCrash(context),
                        child: const Text('Native crash…'),
                      ),
                      OutlinedButton(
                        onPressed: () => _act(() async {
                          await Tracer.startCollection();
                        }),
                        child: const Text('Start'),
                      ),
                      OutlinedButton(
                        onPressed: () => _act(Tracer.stopCollection),
                        child: const Text('Stop'),
                      ),
                      OutlinedButton(
                        onPressed: () => _act(() async {
                          await Tracer.stopAndClearCollection();
                        }),
                        child: const Text('Stop and clear'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  SelectableText(_status),
                ],
              ),
            ),
          ),
        ),
      );
}
