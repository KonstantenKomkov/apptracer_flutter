# П. 29. Управляемые обновления desktop Sentry SDK

**Статус:** выполнена без изменения production pin. **Приоритет:** P1. **Сложность:** L.

[Инвентарь внутренних API и candidate-процесс](../desktop-sentry-dependencies.md),
[установка и обновления](../desktop-migration.md#sentry-upgrades).

Связанный общий план: [development_v1.md](development_v1.md).
Общая матрица Flutter поддерживается в [№26](task-26-flutter-version-ci.md);
здесь рассматривается только Sentry/desktop native compatibility.

## Контекст

`apptracer_flutter_desktop` закрепляет `sentry_flutter: 9.30.1`. Адаптер использует
внутренние Dart imports, `invalid_use_of_internal_member`, FFI-структуры и функции
`sentry-native`. Это позволило реализовать consent, owned queue, native lifecycle и
символизацию, но делает обновление зависимости потенциально ломающим даже без
изменения публичного API Sentry.

Простое расширение constraint или автоматический merge major update неприемлемы:
нужно проверять реальные native очереди, crash handler, stop/clear и exact-build
символы на трёх desktop-платформах.

Основные места:

- `packages/apptracer_flutter_desktop/pubspec.yaml`;
- `packages/apptracer_flutter_desktop/lib/src/sentry_desktop_tracer.dart`;
- `packages/apptracer_flutter_desktop/lib/src/linux_lifecycle.dart`;
- `packages/apptracer_flutter_desktop/lib/src/windows_lifecycle.dart`;
- `packages/apptracer_flutter_desktop/lib/src/sdk_configuration.dart`;
- `.github/workflows/{linux,macos,macos-symbols,windows,windows-runtime}.yml`;
- `docs/desktop-migration.md` и platform acceptance-протоколы.

## Цель

Получить регулярный безопасный процесс оценки новых Sentry SDK, постепенно сократить
зависимость от внутренних API и обновлять pin только после полной приёмки.

## Сделать

1. Составить инвентарь внутренних API и нативных символов, от которых зависит
   адаптер: источник, назначение, доступная публичная альтернатива и тест, который
   обнаружит несовместимость.
2. Добавить scheduled/dispatch candidate workflow, который разрешает новую версию
   Sentry в изолированном candidate checkout/worktree и не меняет production pin.
   Исключить автоматический merge и публикацию.
3. Для каждого candidate сначала выполнить resolver, analyze и unit tests, затем
   Linux/macOS/Windows release builds и существующие loopback/runtime suites.
4. Обязательно проверить deferred bootstrap, offline/retry, in-flight cancellation,
   stop/clear/revoke, account isolation, native crash и отсутствие replay после
   отзыва. Сборка и HTTP 200 не заменяют эти сценарии.
5. Проверить client Dart/native source maps, native handler packaging и
   отрицательные missing/mismatched symbol scenarios. Зафиксировать фактические
   версии Sentry Flutter/Cocoa/native и toolchain для каждой ОС.
6. По результатам candidate либо открыть понятный compatibility report, либо
   подготовить отдельный PR с изменением pin и адаптацией кода. В PR приложить
   полный список прогонов и новых ограничений.
7. Там где Sentry предоставляет публичный эквивалент, заменить internal API отдельными
   небольшими изменениями с регрессионными тестами. Не переписывать lifecycle и
   обновлять major SDK одним безразборным изменением.
8. Перед выпуском нового pin выполнить live Tracer smoke и hosted consumer без
   monorepo overrides. Обновить docs и сохранить возможность отката на предыдущую
   проверенную пару SDK.

## Критерии приёмки

- Candidate updates регулярно проверяются без изменения стабильной зависимости.
- По каждому candidate есть машиночитаемый/текстовый результат по всем трём ОС,
  включая явные skipped/blocked этапы.
- Production pin меняется только после успешных unit, release, lifecycle, native
  crash, offline/retry и symbol checks на поддерживаемых desktop-платформах.
- Нет скрытого расширения dependency constraint при наличии unresolved internal API
  compatibility failure.
- Использование внутренних API задокументировано и уменьшается там, где появилась
  проверенная публичная альтернатива.
- Hosted consumer и live Tracer smoke пройдены до объявления новой версии
  поддерживаемой; rollback path сохранён.

## Проверки

- Существующие Linux, macOS и Windows preparation/runtime workflows.
- Desktop `flutter analyze --fatal-infos` и `flutter test` для candidate и pin.
- External consumer без overrides, `dart pub publish --dry-run`.
- Live Tracer только на финальном release candidate; токены не попадают в CI logs
  и acceptance artifacts.

## Не входит

- Немедленное обновление на последнюю major-версию без полной приёмки.
- Автоматическая публикация новых версий пакета.
- Ослабление consent/clear ради совместимости с SDK.
