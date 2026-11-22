# П. 33. Миграция desktop-адаптера на Sentry 10.x

**Статус:** открыта. **Приоритет:** P1. **Сложность:** XL.

Связанные документы: [инвентарь SDK](../desktop-sentry-dependencies.md),
[процесс candidate-обновлений](task-29-desktop-sentry-upgrades.md),
[общий план](development_v1.md).

## Контекст

Production pin — `sentry_flutter 9.30.1`. Candidate 10.6.0 не проходит analyze:
удалены используемые integrations и изменены options/logger API. Кандидат также
повышает минимальный Flutter до 3.44 и меняет упаковку Apple на Swift Package
Manager. Linux/Windows lifecycle зависит от внутренних FFI-структур SDK.

## Цель

Перенести desktop-адаптер на конкретную принятую версию Sentry 10.x без ослабления
consent, stop/clear, owned queue, native crash и exact-build symbolication.
Если полный переход невозможен без неприемлемых регрессий, получить доказанный
блокер и сохранить рабочий production pin.

## Сделать

1. Выбрать точную 10.x candidate-версию по актуальному resolver и зафиксировать
   изменения минимального Flutter/Dart, CocoaPods/SPM и native SDK.
2. Составить mapping удалённых API на публичные эквиваленты. Внутренние API без
   альтернативы изолировать узким слоем и проверять ABI/структуру на каждом candidate.
3. Обновить adapter, example, podspec/SPM и native lifecycle только после анализа
   новых исходников. Не оставлять compatibility shims, имитирующие успешный старт.
4. Отдельно принять решение о major-версии `apptracer_flutter_desktop` и новом
   минимальном Flutter; синхронизировать pubspec, changelog и migration guide.
5. Прогнать unit, release и runtime-матрицу Linux/macOS/Windows: deferred bootstrap,
   offline/retry, cancellation, stop/clear/revoke, account isolation, native crash,
   no-replay, Dart/native symbols и missing/mismatched maps.
6. Проверить hosted consumer без overrides и live Tracer smoke перед объявлением
   новой версии поддерживаемой. Не публиковать пакет автоматически.
7. Если недоступная ОС/device/live среда блокирует acceptance, влить только
   самостоятельно проверенные подготовительные изменения отдельным PR, а смену
   production pin оставить открытой с конкретным протоколом блокера.

## Критерии приёмки

- Точный 10.x pin проходит analyze/unit и все обязательные platform suites, либо
  production pin не изменён, а блокер подтверждён артефактами.
- Consent и очистка не ослаблены; пропущенный suite не считается успешным.
- Использование внутренних API уменьшено там, где есть проверенная публичная замена.
- Hosted consumer и live smoke подтверждены до статуса supported; rollback описан.
- Документация соответствует фактически принятой версии и минимальному Flutter.

## Проверки

- Desktop `flutter analyze --fatal-infos`, `flutter test`, publish dry-run.
- Все reusable desktop workflows с candidate pin и их machine-readable reports.
- External hosted consumer и финальный live Tracer smoke.

## Не входит

- Простое расширение constraint при красном candidate.
- Автоматическая публикация или объявление поддержки по успешной сборке.
- Одновременный несвязанный рефакторинг общего facade.
