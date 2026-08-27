import 'dart:ffi';

/// Кадр, который проверка 16 из docs/live-verification-plan.md должна увидеть
/// названным. Держится отдельной функцией с говорящим именем и запретом на
/// инлайн: в отчёте Tracer его имя — и есть результат проверки.
@pragma('vm:never-inline')
int _faultingAddress() {
  // Адрес заведомо вне пользовательского пространства (88 ТБ), а не ноль:
  // нулевые страницы — узнаваемый шаблон, и не хочется гадать, не превратит ли
  // его рантайм в обычное исключение. Строка вместо литерала — чтобы значение
  // не свернулось в константу на этапе компиляции.
  return int.parse('5000000000000', radix: 16);
}

/// Kills the process with a fault raised *by Dart AOT code itself*.
///
/// The point is where the faulting instruction sits. A signal raised from
/// Kotlin — the `crashNatively` button — unwinds through libc and ART, and the
/// report carries no frames from `libapp.so` at all, so it says nothing about
/// whether Dart symbols were applied. A store through a `dart:ffi` pointer
/// compiles to a plain instruction inside `_kDartIsolateSnapshotInstructions`,
/// which is exactly the region the staged `libapp.so` symbols describe.
@pragma('vm:never-inline')
Never crashInsideDartCode() {
  final pointer = Pointer<Uint8>.fromAddress(_faultingAddress());
  pointer.value = 0x2a;
  throw StateError('процесс должен был упасть на записи по адресу выше');
}
