import 'package:apptracer_flutter/apptracer_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _nativeFailures = MethodChannel('ru.apptracer.flutter.example/native');
const _user =
    String.fromEnvironment('TRACER_TEST_USER', defaultValue: 'test-A');
const _case =
    String.fromEnvironment('TRACER_TEST_CASE', defaultValue: 'consent');
const _iosToken = String.fromEnvironment('TRACER_IOS_APP_TOKEN');
const _options = TracerOptions(
  nativeInitialization: TracerNativeInitialization.deferred,
  iosAppToken: _iosToken == '' ? null : _iosToken,
  debug: !kReleaseMode,
  initialCustomKeys: <String, String>{'consent_test_user': _user},
);

void main() {
  Tracer.initialize(
    options: _options,
    // No network warm-up: this entrypoint must remain silent before permission.
    appRunner: () => runApp(const ConsentVerificationApp()),
  );
}

/// An explicit verification harness; it does not store or verify legal consent.
class ConsentVerificationApp extends StatelessWidget {
  const ConsentVerificationApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Native collection verification',
        home: const _ConsentPage(),
      );
}

class _ConsentPage extends StatefulWidget {
  const _ConsentPage();

  @override
  State<_ConsentPage> createState() => _ConsentPageState();
}

class _ConsentPageState extends State<_ConsentPage> {
  TracerCollectionResult? _result;
  String _message = 'Bootstrap completed without starting collection.';
  bool _preserveReports = false;
  int _generation = 0;
  int _pending = 0;

  Future<void> _operation(
    Future<TracerCollectionResult> Function() perform,
  ) async {
    final generation = ++_generation;
    setState(() => _pending++);
    try {
      final result = await perform();
      if (mounted && generation == _generation) {
        setState(() {
          _result = result;
          _message = result.state == TracerCollectionState.restartRequired
              ? 'Collection cannot resume until a new process starts.'
              : 'Result: ${result.state.name}${result.reason == null ? '' : ' (${result.reason})'}';
        });
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _message = 'Operation failed: $error');
      }
    } finally {
      if (mounted) setState(() => _pending--);
    }
  }

  Future<void> _recordProbe() async {
    await Tracer.setUserId(_user);
    await Tracer.setCustomKey(key: 'consent_test_case', value: _case);
    Tracer.log('$_case breadcrumb for $_user', category: 'consent_probe');
    await Tracer.recordLog('$_case native log for $_user');
    await Tracer.recordError(
      StateError('Native consent probe: $_case / $_user'),
      StackTrace.current,
      issueKey: 'consent_lifecycle_dart',
    );
    if (mounted) {
      setState(() => _message = Tracer.isEnabled
          ? 'Probe submitted; verify delivery in Tracer.'
          : 'Probe discarded while collection is off.');
    }
  }

  Future<void> _nativeProbe(String method) async {
    try {
      await _nativeFailures.invokeMethod<void>(method);
    } catch (error) {
      if (mounted) setState(() => _message = 'Native probe failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final android = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    return Scaffold(
      appBar: AppBar(title: const Text('Native consent verification')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text('User: $_user; case: $_case'),
          Text('Dart collection: ${Tracer.isEnabled ? 'on' : 'off'}'),
          Text('Native result: ${_result?.state.name ?? 'not queried'}'),
          Text('Pending operations: $_pending'),
          const SizedBox(height: 12),
          Text(_message),
          SwitchListTile(
            title: const Text('Recover reports from the same authorized user'),
            subtitle: const Text(
                'Off by default. A prior purge obligation overrides this choice.'),
            value: _preserveReports,
            onChanged: (value) => setState(() => _preserveReports = value),
          ),
          FilledButton(
            onPressed: () => _operation(() => Tracer.startCollection(
                  _options.copyWith(preservePreviousReports: _preserveReports),
                )),
            child: const Text('Start after application permission'),
          ),
          OutlinedButton(
            onPressed: () => _operation(Tracer.stopAndClearCollection),
            child: const Text('Revoke / logout: stop and clear'),
          ),
          TextButton(
            onPressed: () => _operation(Tracer.getCollectionState),
            child: const Text('Query actual state'),
          ),
          OutlinedButton(
            onPressed: _recordProbe,
            child: const Text('Dart error + user + key + breadcrumb + log'),
          ),
          if (android) ...<Widget>[
            const Divider(),
            const Text(
                'Fatal probes end this process. They are available while off to verify absence of collection.'),
            OutlinedButton(
              onPressed: () => _nativeProbe('crashJvm'),
              child: const Text('JVM fatal: ends process'),
            ),
            OutlinedButton(
              onPressed: () => _nativeProbe('crashNatively'),
              child: const Text('Native SIGSEGV: ends process'),
            ),
            OutlinedButton(
              onPressed: () => _nativeProbe('blockMainThread'),
              child: const Text('ANR: blocks main thread for 120 seconds'),
            ),
          ],
        ],
      ),
    );
  }
}
