import 'package:apptracer_flutter_aurora/apptracer_flutter_aurora.dart';
import 'package:flutter/material.dart';

void main() => runApp(const MaterialApp(home: DiagnosticScreen()));

class DiagnosticScreen extends StatefulWidget {
  const DiagnosticScreen({super.key});

  @override
  State<DiagnosticScreen> createState() => _DiagnosticScreenState();
}

class _DiagnosticScreenState extends State<DiagnosticScreen> {
  late final result = AuroraTracer.probe().then((data) {
    debugPrint(
      'Tracer Native ${data['sdkVersion']}, '
      'crashDumperConfigured=${data['crashDumperConfigured']}',
    );
    return data;
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Tracer для Авроры')),
    body: Padding(
      padding: const EdgeInsets.all(24),
      child: FutureBuilder<Map<String, Object?>>(
        future: result,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return SelectableText('Ошибка проверки SDK: ${snapshot.error}');
          }
          final data = snapshot.data;
          if (data == null) return const CircularProgressIndicator();
          final handler = switch (data['crashDumperConfigured']) {
            true => 'настроен',
            false => 'не настроен',
            _ => 'нет доступа к системной настройке',
          };
          return SelectableText(
            'Tracer Native ${data['sdkVersion']} загружен.\n'
            'Системный crash-dumper: $handler.',
          );
        },
      ),
    ),
  );
}
