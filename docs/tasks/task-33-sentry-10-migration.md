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
При блокере сохранить рабочий production pin и оставить миграцию открытой.

## Сделать

1. Выбрать точную 10.x candidate-версию по актуальному resolver и зафиксировать
   изменения минимального Flutter/Dart, CocoaPods/SPM и native SDK.
2. Составить mapping удалённых API на публичные эквиваленты. Внутренние API без
   альтернативы изолировать узким слоем и проверять ABI/структуру на каждом candidate.
3. Обновить adapter, example, podspec/SPM и native lifecycle после анализа
   новых исходников. Сверить точные версии в consumer-проверках и исключение
   для предупреждения pub в `tool/publish_dry_run.sh` с принятым кандидатом.
4. Отдельно принять решение о major-версии `apptracer_flutter_desktop` и новом
   минимальном Flutter. Согласовать pubspec адаптера и example с матрицей CI:
   общий analyze сейчас запускает desktop на Flutter 3.35.7, ниже минимума 10.6.0.
   Сохранить проверку заявленного минимума общих пакетов. Обновить changelog и migration guide.
5. Прогнать unit, release и runtime-матрицу Linux/macOS/Windows: deferred bootstrap,
   offline/retry, cancellation, stop/clear/revoke, account isolation, native crash,
   no-replay, Dart/native symbols и missing/mismatched maps.
6. До выпуска проверить изолированный consumer с экспортом изменённого адаптера,
   hosted-зависимостями без overrides и точной 10.x в lockfile. Провести live
   Tracer smoke на этом кандидате. После отдельной публикации проверить чистую
   установку именно нового адаптера с pub.dev без path/git/overrides.
7. Если миграция заблокирована, указать проверенную версию, попытку адаптации
   или недоступную среду, упавший/пропущенный этап и условие возобновления.
   Самостоятельно проверенные подготовительные изменения можно выделить в отдельный PR.

## Критерии приёмки

- Для завершения миграции точный 10.x pin проходит analyze/unit и обязательные
  platform suites в пределах [проверенной поддержки](../platform-matrix.md#desktop-and-aurora-os).
  Уже известный сбой analyze в №29 — исходное состояние. Протокол блокера
  фиксирует незавершённую работу без смены production pin.
- Consent и очистка не ослаблены; пропущенный suite не считается успешным.
- Использование внутренних API уменьшено там, где есть проверенная публичная замена.
- Для PR приложены lockfile изолированного consumer, результат live smoke и
  инструкция отката. Статус supported требует также проверки опубликованного адаптера.
- Документация соответствует фактически принятой версии и минимальному Flutter.

## Проверки

- Desktop `flutter analyze --fatal-infos`, `flutter test`, publish dry-run.
- Все reusable desktop workflows с candidate pin и их machine-readable reports.
- Изолированный consumer кандидата и финальный live Tracer smoke; после выпуска —
  consumer опубликованной версии по [процедуре выпуска](../publishing.md).

## Не входит

- Простое расширение constraint при красном candidate.
- Автоматическая публикация или объявление поддержки по успешной сборке.
- Одновременный несвязанный рефакторинг общего facade.
