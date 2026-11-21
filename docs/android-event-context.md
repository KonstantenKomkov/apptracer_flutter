# Изоляция контекста Android-событий

Проверено 21 ноября 2026 на Tracer Android SDK 1.6.2. Это протокол задачи №24,
а не свидетельство о других версиях SDK или платформах.

## Механизм

В SDK 1.6.2 нет per-event API для custom properties. `CrashLoggerInternal`
синхронно читает `SystemState` при вызове `report`, сохраняет отчёт и лишь затем
передаёт его асинхронному uploader. Поэтому адаптер применяет карту события к
native scope внутри общей для всех Flutter engine критической секции и в `finally`
восстанавливает прежние значения.

Снимок берётся из фактического `Tracer.stateStorage.currentSystemState.properties`,
поэтому сохраняются также значения, установленные нативным хостом. Постоянные ключи,
удалённые из `TracerEvent` в `beforeSend`, временно удаляются и из native scope.
Одноразовое переопределение не меняет постоянное значение. Diagnostic-поля явно
удаляются, если у следующего события их нет. `setCustomKey`, `removeCustomKey` и
отправки используют тот же lock; исключение отчёта не пропускает восстановление.

## Regression и JVM-проверки

`EventContextTest` на исходной реализации падал на первом событии: `endpoint`,
переопределённый `collision`, `dart.needs_symbolication` и `dart.build_id` оставались
в native scope. После исправления проходят четыре теста:

- последовательные события и коллизия одноразового/постоянного ключа;
- удаление и изменение постоянного ключа через итоговую карту `beforeSend`;
- восстановление scope после исключения нативного reporter;
- шесть конкурентных отчётов без смешивания свойств.

Полный `:apptracer_flutter_android:testDebugUnitTest` также прошёл.

## Release/R8 loopback

- Flutter 3.47.4 / Dart 3.13.3, Android 15 API 35, arm64, новый disposable AVD.
- SDK/BOM/Gradle plugin 1.6.2, release с R8 и deferred lifecycle.
- Placeholder app token, mapping/native-symbol upload выключены; live-аккаунт и
  реальные пользовательские данные не использовались.
- Entrypoint `lib/android_native_verification.dart`, сценарий `event-context`.
- Приняты ровно два `NON_FATAL` multipart-отчёта; свойства проверены внутри
  фактически полученного `uploadBean`, а не только в Dart model.

В первом отчёте `endpoint=/orders`, `collision=filtered-value`,
`dart.needs_symbolication=true` и ожидаемый `dart.build_id`. Постоянный `tenant` и
одноразовый `transientRemove`, удалённые в `beforeSend`, отсутствуют. Во втором
отчёте `tenant=global-tenant` и `collision=global-value`; одноразовые и
diagnostic-поля первого отчёта отсутствуют. После сценария stop/clear завершился
состоянием `disabled`.

Воспроизведение проверки захвата:

```sh
python3 tool/check_android_event_context.py <каталог-verification>
```

Сырые body/headers могут содержать SDK credentials и не включаются в репозиторий.

## Аудит iOS

Это отдельный статический аудит `AppTracerFlutterPlugin.swift`, не доказательство
из Android-приёмки. iOS создаёт новый `properties` для каждого
`TracerNonFatalModel`; одноразовые и diagnostic-значения не записываются через
`update(properties:)`, поэтому подтверждённого в коде пути их утечки между
Dart-событиями нет. Постоянные ключи по-прежнему обновляются через
`TracerServiceProtocol.update(properties:)`. Их слияние с per-event model и удаление
через `beforeSend` этой задачей на устройстве не проверялись; iOS-фильтрация
постоянных native полей не сертифицируется этим протоколом.
