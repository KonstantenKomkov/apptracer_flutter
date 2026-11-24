import 'dart:io';

import 'package:apptracer_flutter/apptracer_flutter.dart';
import 'package:apptracer_flutter_aurora/apptracer_flutter_aurora.dart';
import 'package:flutter/material.dart';

Future<void> main() => Tracer.initialize(
  options: const TracerOptions(
    nativeInitialization: TracerNativeInitialization.deferred,
  ),
  appRunner: () => runApp(const MaterialApp(home: DiagnosticScreen())),
);

class DiagnosticScreen extends StatefulWidget {
  const DiagnosticScreen({super.key});

  @override
  State<DiagnosticScreen> createState() => _DiagnosticScreenState();
}

class _DiagnosticScreenState extends State<DiagnosticScreen> {
  final token = TextEditingController();
  final dsn = TextEditingController();
  final account = TextEditingController(text: 'example');
  late final probe = AuroraTracer.probe();
  var state = TracerCollectionState.disabled;
  var preserve = false;
  var busy = false;
  String? receipt;

  @override
  void dispose() {
    token.dispose();
    dsn.dispose();
    account.dispose();
    super.dispose();
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
    } catch (error) {
      receipt = 'Ошибка операции (${error.runtimeType})';
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> start() async {
    final options = TracerOptions(
      appToken: token.text.trim(),
      dsn: dsn.text.trim().isEmpty ? null : dsn.text.trim(),
      auroraAccountScope: account.text.trim(),
      release: '2.0.0',
      dist: '1',
      preservePreviousReports: preserve,
      nativeInitialization: TracerNativeInitialization.deferred,
      deliveryListener: (event) {
        if (mounted)
          setState(
            () => receipt =
                '${event.backend} · ${event.operation} · ${event.reason}',
          );
      },
    );
    final result = await Tracer.startCollection(options);
    state = result.state;
    receipt = result.reason;
    if (result.isEnabled) {
      await Tracer.setCustomKey(key: 'sample', value: 'aurora');
      Tracer.log('Сбор включён в примере Авроры');
    }
  }

  Future<void> stop() async {
    final result = await Tracer.stopAndClearCollection();
    state = result.state;
    receipt = result.reason;
  }

  Future<void> sendError() async {
    try {
      throw StateError('Тестовое исключение примера Авроры');
    } catch (error, stack) {
      await Tracer.recordError(error, stack);
    }
  }

  Future<void> crash() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Завершить приложение?'),
        content: const Text(
          'После падения откройте пример снова и включите восстановление с тем же аккаунтом.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Вызвать SIGABRT'),
          ),
        ],
      ),
    );
    if (confirmed == true && Tracer.isEnabled) {
      await Tracer.recordLog('Тестовое падение Flutter runner');
      Process.killPid(pid, ProcessSignal.sigabrt);
    }
  }

  Widget field(
    String label,
    TextEditingController controller, {
    bool secret = false,
  }) => TextField(
    controller: controller,
    enabled: !busy && !Tracer.isEnabled,
    obscureText: secret,
    autocorrect: false,
    enableSuggestions: false,
    decoration: InputDecoration(labelText: label),
  );

  @override
  Widget build(BuildContext context) {
    final enabled = Tracer.isEnabled;
    return Scaffold(
      appBar: AppBar(title: const Text('Tracer для Авроры')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          FutureBuilder<Map<String, Object?>>(
            future: probe,
            builder: (context, snapshot) {
              if (snapshot.hasError)
                return const Text('Не удалось загрузить Tracer Native');
              final sdk = snapshot.data;
              if (sdk == null) return const LinearProgressIndicator();
              final handler = switch (sdk['crashDumperConfigured']) {
                true => 'настроен',
                false => 'не настроен',
                _ => 'настройка скрыта системой',
              };
              return Text(
                'Tracer Native ${sdk['sdkVersion']} · crash-dumper: $handler',
              );
            },
          ),
          Text('aurora-native · ${state.name}'),
          field('App token', token, secret: true),
          field('Sentry DSN для Dart (необязательно)', dsn, secret: true),
          field('Область согласия аккаунта', account),
          SwitchListTile(
            title: const Text('Восстановить разрешённые отчёты этого аккаунта'),
            value: preserve,
            onChanged: busy || enabled
                ? null
                : (value) => setState(() => preserve = value),
          ),
          FilledButton(
            onPressed: busy || enabled ? null : () => run(start),
            child: const Text('Включить сбор'),
          ),
          OutlinedButton(
            onPressed: busy ? null : () => run(stop),
            child: const Text('Остановить и очистить'),
          ),
          OutlinedButton(
            onPressed: busy || !enabled ? null : () => run(sendError),
            child: const Text('Отправить ошибку Dart'),
          ),
          OutlinedButton(
            onPressed: busy || !enabled ? null : () => run(crash),
            child: const Text('Проверить нативное падение'),
          ),
          if (receipt != null) SelectableText(receipt!),
        ],
      ),
    );
  }
}
