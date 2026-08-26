// Прогон сценариев из docs/live-verification-plan.md, шаг 3.4, без ручных
// нажатий.
//
// Что тест делает и чего не делает
// --------------------------------
// Делает: запускает настоящее приложение (тот же `main`, что и в проде),
// нажимает кнопки в правильном порядке и проверяет то, что видно со стороны
// Dart, — что сбор включён, что ошибки долетели до обработчиков, что
// `stopCollection` действительно выключает сбор.
//
// Не делает: не проверяет, что событие доехало до Tracer и как оно там
// выглядит. У Tracer нет публичного API на чтение событий — только на загрузку
// символов и сорсмап. Заголовок, группировку, вкладки «Логи» и «Данные»
// придётся смотреть глазами; в конце теста печатается готовый список.
//
// Нативный краш и ANR сюда не входят намеренно: первый убивает процесс, второй
// вешает главный поток, и в обоих случаях драйвер теряет соединение и объявляет
// прогон упавшим. Их две кнопки в приложении, и делать их надо руками, после
// теста.
//
// Запуск: make live-check

import 'package:apptracer_flutter/apptracer_flutter.dart';
import 'package:apptracer_flutter_example/main.dart' as app;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('прогоняет сценарии проверок 1-6 и 18',
      (WidgetTester tester) async {
    app.main();
    await tester.pumpAndSettle();

    // Инициализация асинхронная: `main` её не ждёт, а нативная сторона
    // отвечает через канал. Проверять `isEnabled` сразу после `pumpAndSettle`
    // — это гонка, которая падает через раз.
    await _waitUntil(
      tester,
      () => Tracer.isEnabled,
      reason: 'Сбор так и не включился. На Android это почти всегда значит, '
          'что сборку запустили без -Ptracer.enabled=true, и SDK Tracer нет в '
          'classpath. См. docs/live-verification-plan.md, шаг 3.3.',
    );

    // Breadcrumbs и кастомный ключ — до ошибки: в событие попадает то, что
    // было выставлено раньше него.
    await _tap(tester, 'Добавить breadcrumb');
    await _tap(tester, 'Добавить breadcrumb');
    expect(Tracer.breadcrumbs.length, 2);

    await _tap(tester, 'Задать кастомный ключ');

    // Проверки 1, 2, 3, 5, 6 — всё в одном событии.
    await _tap(tester, 'Отправить пойманную ошибку');

    // Проверка 4: две ошибки, которые обязаны попасть в разные группы.
    // Проверка 4 наполовину: синхронный бросок и бросок из build() обязаны
    // попасть в разные группы.
    await _tapExpectingError(tester, 'Бросить синхронно', isStateError);
    //
    // «Бросить асинхронно» и «Бросить из future без await» сюда не входят, и
    // это ограничение харнесса, а не пакета. Таймер, созданный во время
    // нажатия, наследует зону, активную в момент создания, — а `tester.tap`
    // вызывается из зоны теста, не из защищённой зоны приложения. Ошибка
    // уходит тестовому фреймворку, тот обрывает тест, и до нашего обработчика
    // она не доходит вовсе. В настоящем приложении нажатие приходит через
    // конвейер событий, зарегистрированный внутри зоны приложения, и всё
    // работает — это и видно в консоли Tracer. Обе кнопки остаются в ручном
    // списке ниже.

    // Ошибка внутри build(): кнопка работает как переключатель, второе
    // нажатие убирает сломанный виджет с экрана. Пока он там, каждая
    // пересборка бросает заново, поэтому ошибок накапливается несколько — их
    // надо снять все, иначе следующий takeException вернёт агрегат вместо
    // ожидаемого StateError.
    await _tapExpectingError(
        tester, 'Бросить внутри build() виджета', isStateError);
    await _tap(tester, 'Бросить внутри build() виджета');
    _drainExceptions(tester);

    // Проверка 18 — последней: на Android нативный SDK обратно уже не
    // включится, процесс придётся перезапускать.
    await _tap(tester, 'Остановить сбор');
    expect(
      Tracer.isEnabled,
      isFalse,
      reason: 'stopCollection не выключил сбор — это блокер.',
    );

    // Ошибка после остановки не должна никуда уехать. Со стороны Dart видно
    // только то, что клиент выключен; отсутствие события в консоли — вторая
    // половина проверки, и она ручная.
    await _tapExpectingError(tester, 'Бросить синхронно', isStateError);
    expect(Tracer.isEnabled, isFalse);

    // Страховка от того, что уже случалось: сценарий тихо выпал из теста при
    // правке соседних строк, тест остался зелёным, а события в Tracer не было.
    // Список нажатий обязан совпадать дословно.
    expect(
      _tapped,
      <String>[
        'Добавить breadcrumb',
        'Добавить breadcrumb',
        'Задать кастомный ключ',
        'Отправить пойманную ошибку',
        'Бросить синхронно',
        'Бросить внутри build() виджета',
        'Бросить внутри build() виджета',
        'Остановить сбор',
        'Бросить синхронно',
      ],
      reason: 'Набор сценариев изменился. Если это намеренно — обновите список '
          'здесь и в _printChecklist, иначе проверка молча перестанет что-то '
          'покрывать.',
    );

    _printChecklist();
  });
}

/// Кнопки, которые тест успел нажать, по порядку.
final List<String> _tapped = <String>[];

/// Нажимает кнопку с подписью [label], прокрутив до неё.
///
/// `ListView` разрушает виджеты за пределами экрана, поэтому `find.text` не
/// видит того, что не построено, — а порядок нажатий здесь диктуется логикой
/// проверок, а не вёрсткой, и ходить приходится в обе стороны. Поэтому перед
/// каждым поиском список возвращается в начало и прокручивается вниз: так
/// нажатие не зависит от того, где мы оказались после предыдущего.
Future<void> _tap(WidgetTester tester, String label) async {
  final finder = find.text(label);
  final scrollable = find.byType(Scrollable).first;

  tester.state<ScrollableState>(scrollable).position.jumpTo(0);
  await tester.pumpAndSettle();

  await tester.scrollUntilVisible(finder, 120, scrollable: scrollable);
  expect(finder, findsOneWidget, reason: 'Кнопки «$label» нет на экране.');

  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  _tapped.add(label);
  await _settle(tester);
}

/// То же, но ошибка ожидаема: без этого её поднимет тестовый фреймворк и
/// прогон упадёт на сценарии, который отработал правильно.
Future<void> _tapExpectingError(
  WidgetTester tester,
  String label,
  Matcher matcher,
) async {
  await _tap(tester, label);
  expect(tester.takeException(), matcher);
}

/// Снимает все накопившиеся ошибки, чтобы они не мешали следующей проверке.
void _drainExceptions(WidgetTester tester) {
  while (tester.takeException() != null) {
    // Значение не нужно: ошибки ожидаемы и уже уехали в Tracer.
  }
}

/// Ждёт, пока [condition] станет истинным, но не дольше [timeout].
Future<void> _waitUntil(
  WidgetTester tester,
  bool Function() condition, {
  required String reason,
  Duration timeout = const Duration(seconds: 15),
}) async {
  final Stopwatch elapsed = Stopwatch()..start();
  while (!condition() && elapsed.elapsed < timeout) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(condition(), isTrue, reason: reason);
}

/// Даёт отработать таймерам и каналу к нативной стороне.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

void _printChecklist() {
  // ignore: avoid_print
  print('''

=== Прогон закончен. Осталось сверить глазами в консоли Tracer ===

Раздел «Сбои», через пару минут. Тест отправил три группы:

  1. DartError: FormatException: could not parse the response  [EXAMPLE-PARSE], WARNING
  2. DartError: StateError: Bad state: synchronous Dart failure
  3. DartError: StateError: Bad state: failure raised inside build()

Проверка 1  — все три появились.
Проверка 2  — заголовок читается как DartError: <ТипDart>: <сообщение>.
Проверка 3  — в стектрейсе кадры Dart с package:apptracer_flutter_example/main.dart.
              На Android это главная проверка: там легко получить вместо них
              кадры JNI, одинаковые у всех ошибок.
Проверка 4  — 2 и 3 лежат в РАЗНЫХ группах (полностью закрывается ручным прогоном,
              см. ниже). На iOS это же закрывает проверку 10: группировка идёт по
              синтетическому issueKey, который виден в заголовке группы.
Проверка 5  — событие 1, вкладка «Логи»: [info] ui | user tapped the breadcrumb button
              (на iOS это проверка 11)
Проверка 6  — событие 1, вкладка «Данные»: checkout_step = 3, dart.exception_type
Проверка 18 — после «Остановить сбор» тест нажал «Бросить синхронно» ещё раз.
              Счётчик у группы 2 должен остаться равным 1.

Что тест не нажимает — руками, запустив приложение (make android):

  «Бросить асинхронно» и «Бросить из future без await». Ошибка из таймера
  уходит в зону теста, а не в защищённую зону приложения, и до обработчика не
  доходит; в обычном запуске работает. См. комментарий в теле теста. Должны
  появиться ещё две группы:

    4. DartError: FormatException: asynchronous failure
    5. DartError: TimeoutException: unawaited future failure

  «Уронить процесс нативно» и «Заблокировать главный поток (ANR)» — проверки 7
  и 8. Первая убивает процесс, вторая вешает главный поток; драйвер в обоих
  случаях теряет соединение, поэтому в автопрогон они не входят.
''');
}
