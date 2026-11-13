# Сквозная приёмка Android SDK 1.6.1

Протокол Android №21 от 10 ноября 2026. **Приёмка принята 13 ноября с известным
внешним ограничением Kotlin-символизации:** класс и метод восстановлены, но
консоль показывает `KotlinCrashProbe.java:14` вместо `KotlinCrashProbe.kt:6`.
Локальные проверки, device-матрица и доставка финальной live-серии завершены.
По согласованному решению дефект вынесен отдельно и не блокирует №22 и выпуск;
сам дефект остаётся открытым. Новая live-проверка этим решением не заявляется,
а готовность пакетов и публикация проверяются отдельно в №22.

[Машиночитаемые результаты](android-sdk-1.6.1-acceptance.json),
[минимальный reproducer](../tool/fixtures/android-sdk161/kotlin-symbolication/README.md).

## Среда и исходники

- SDK/BOM/Gradle plugin 1.6.1 из Maven Central; native bindings 0.1.41-android.
- Flutter 3.47.4 / Dart 3.13.3, JDK 21.0.8, Gradle 8.12, AGP 8.9.1,
  Kotlin 2.1.0, R8 8.9.32.
- Release/R8, arm64-v8a, Android 15 / API 35, отдельный disposable AVD.
  Физическое устройство не использовалось.
- Базовый commit `6387293`; изменения №21 добавляют метку запуска, отдельные
  обфусцируемые Java/Kotlin crash probes, tombstone-контроли и исправления harness.
  SHA-256 исходных файлов точной финальной сборки сохранены в JSON вместе с
  APK/mapping/buildUuid. Обфускация probes сохраняется.

## Проверки кода

| Проверка | Результат |
| --- | --- |
| Android JVM/JUnit | 31 тест, 0 failures/errors/skipped |
| Ленивый HeapDump provider на реальном SDK | 5 JUnit-тестов |
| Основной Dart lifecycle/facade | 84 теста |
| Android / iOS channel | 2 / 3 теста |
| Web в Chrome | 5 тестов |
| Пример | 1 widget-тест |
| `flutter analyze --fatal-infos` этих пакетов и примера | Пройден |
| `check_sdk140_background.sh`, `check_sdk140_buffers.sh` на 1.6.1 | Пройдены |
| R8 classfile + `check_sdk140_reflection.sh` на 1.6.1 | Пройден |
| R8 без SDK + `check_missing_sdk_lifecycle.sh` | Пройден |
| `check_sdk_runtime_enable.sh`, согласованные наборы JAR | 1.4.0/1.5.2: restartRequired; 1.6.1: enabled |
| Release APK с SDK, без SDK, build disabled, automatic | Собраны и запущены |

Локальные CI-сборки используют placeholder-токены, оба upload-флага выключены,
подключён `tool/android_no_upload.init.gradle`. Live-сборки используют ignored
env-файл, `uploadMapping=true`, `uploadNativeSymbols=false`,
`--no-configuration-cache`. Секреты, сырые HTTP body/header, APK и полные логи
в репозиторий не включены. Запуск удалённого GitHub CI не подтверждён:
локальный `gh` не авторизован.

## Device-матрица

| Сценарии | Наблюдение |
| --- | --- |
| Cold/deferred | SDK выключен до явного старта; cold не отправляет отчёты |
| Runtime disable/enable, deferred и automatic | Ровно `enable-before` + `enable-after`; сообщения во время паузы нет |
| Полный stop/clear, deferred | Файлы удалены, запросов после stop нет; следующий start требует новый процесс |
| Automatic legacy stop | `restartRequired/collection_stopped`; purge не подтверждается, `cleanupVerified=false` |
| Build disabled / отсутствующий SDK | `sdk_build_disabled` / `sdk_missing`, без диагностик и HTTP |
| Offline / in-flight | Контролируемый HTTP 503 / удерживаемый ответ; после revoke нет новых запросов и файлов |
| Account A → B + preserve | В распакованных полях/стеке/логах B есть B, нет маркера A |
| Несколько engine / Activity recreation | Три secondary engine разделяют отзыв; Activity не обходит остановку |
| Ошибки начальной/конечной очистки | Ошибка не разрешает старт и не выдаётся за успешный purge |
| Java / Kotlin crash | JVM CRASH достигает loopback recovery, исходные userId и custom keys сохранены |
| ANR / ANR после pause-enable | По одному ANR в loopback и в финальной live-серии |
| Java/Kotlin/native/ANR после revoke | Во всех четырёх recovery нет crash upload, несмотря на preserve |
| Tombstone, native module отсутствует | Opt-in: один TOMBSTONE; opt-out: ноль crash upload |
| Native module, tombstone выключен | Один MINIDUMP; повторно подтверждено на финальном APK |

Для ANR использованы input-dispatch timeout и кнопка закрытия системного
ANR-диалога. ApplicationExitInfo содержит reason 6 и системную trace.
`am force-stop`/`am crash` не заменяют ANR. Experimental ANR snapshots выключены;
проверяется отчёт из ApplicationExitInfo, а не восстановление watchdog snapshots.

В нескольких JVM-прогонах Android перезаписывал итоговый exit reason значением 9
(EXCESSIVE CPU USAGE). Logcat сохраняет настоящий uncaught probe; JVM CRASH
доставлен. Повторный Kotlin device-прогон получил reason 4. Это наблюдение
эмулятора записано в JSON, а не скрыто под обычным crash exit.

Повторены опциональные №16–17: offline/online исполнение, ленивый provider,
два DiskUsage и один HeapDump upload в локальный приёмник. Provider вызывается
с фоновых потоков. Максимальные UI-паузы 4133/3903 мс: VM-пауза heap dump
сохраняется даже при вызове вне main thread. Offline-удаление sample без retry
остаётся ограничением SDK. Подробный контракт — [№16–17](android-sdk-1.6.1-diagnostics.md).

### Исправления примера и harness

При совместном включении native module и experimental tombstone один SIGSEGV
даёт два отчёта: MINIDUMP и TOMBSTONE с одинаковыми временем и метками.
Теперь example оставляет native module включённым, а tombstone требует явного
`-Ptracer.verificationTombstones=true`. Для проверки системного tombstone:

```text
-Ptracer.verificationNativeModule=false
-Ptracer.verificationTombstones=true   # positive
-Ptracer.verificationTombstones=false  # negative control
```

Публичный Android-пакет уже требовал явного opt-in; его defaults не изменены.
Полная revoke-матрица проверена также на конфигурации с обоими коллекторами.
Финальный live APK и отдельный loopback-контроль проверяют исправленный default.

В harness номер запроса фиксируется до `await`, чтобы параллельные HTTP body
и headers не перезаписывали друг друга. Наблюдение файлов использует `stat`:
удалённый отправителем файл между list и stat не прерывает recovery. Повторный
прогон сохранил обе пары body/headers и завершил recovery без этой гонки.

## Live-серия и точная сборка

Основная принятая серия — `sdk161-20261110-final`, package
`ru.apptracer.flutter.apptracer_flutter_example.consent`, versionName 1.0.0,
versionCode 1. Отдельный системный tombstone — `sdk161-20261110-tombstone`.

| Артефакт финальной сборки | Значение |
| --- | --- |
| buildUuid | `9ff5fc30-dd26-11f1-85f9-dd19426a3bd9` |
| APK SHA-256 | `1883238ea234722bc00c83f30fbe69d79d1fae8324ed1dac169c1edffb401c55` |
| mapping SHA-256 | `23268edab46219556f6780e37ffc3f4f4955c4dcac80861bde62d96fc069189c` |
| Gradle upload | `uploadTracerMappingForConsentRelease`, BUILD SUCCESSFUL |

Из сохранённого `mapping.form-data` извлечён gzip payload: SHA-256 полностью
совпадает с архивным mapping, multipart buildUuid совпадает с финальной сборкой.
Plugin 1.6.1 передаёт mapping целиком, без преобразования записей Kotlin.
Сырые multipart-артефакты содержат plugin token и остаются только локально.

Консоль проверена через открытую авторизованную вкладку пользователя. В каждом
отчёте проверены userId, `verificationRun`, `verificationScenario`, API 35 и дата.
Ссылки сохраняют наблюдавшуюся карточку/выбор события; метка и дата в таблице
однозначно отличают тестовую серию от последующих запусков.

| Отчёт | Событий в серии | Сценарий | Время crash, Москва |
| --- | --- | --- | --- |
| [Dart](https://apptracer.ru/24745424/crashes/report/ERROR/59c5e1ab613270d36ea568cd0b0e1662e622e6de50f44952339eb2d58a223956/11f1-dd28-83ca0040-8f84-253dad88c2c1/filter/date=LAST_24H&extended=1%2C1%2CERROR%2C0%2C0%2CTYPE%2Cnull/) | 1 | `vendor-dart` | 10.11.2026 20:02:28 |
| [Java](https://apptracer.ru/24745424/crashes/report/CRASH/d4d5c9b6f33038584128bfb8487d21811ce7382b5aa90392a3e76f5c2b3eee75/11f1-dd1f-07447e50-8747-d7646dd76cd5/filter/date=LAST_24H&extended=1%2C1%2CCRASH%2C0%2C0%2CTYPE%2Cnull/) | 1 | `jvm-enabled` | 10.11.2026 20:03:27 |
| [Kotlin](https://apptracer.ru/24745424/crashes/report/CRASH/2a21f9a6980066848ff7d126fbe9e16280d7202437cdba392ad454daf72288cd/11f1-dd28-db14f490-b11d-b937c5e462d2/filter/date=LAST_24H&extended=1%2C1%2CCRASH%2C0%2C0%2CTYPE%2Cnull/) | 1 | `kotlin-enabled` | 10.11.2026 20:04:33 |
| [Native MINIDUMP](https://apptracer.ru/24745424/crashes/report/NATIVE/44b3e18d5c931c81cea96a83f41b863464bca6c0d3ffcfd28000df042c143d53/11f1-dd29-03bfb8d0-8747-d7646dd76cd5/filter/date=LAST_24H&extended=1%2C1%2CNATIVE%2C0%2C0%2CTYPE%2Cnull/) | 1 | `native-enabled` | 10.11.2026 20:05:54 |
| [ANR](https://apptracer.ru/24745424/crashes/report/ANR/73afcc99e3ccdb60fba31b50cb4b022b76f4f363e0b3ee3ae4af0ae39993ae85/11f1-dd29-3e3d5300-8747-d7646dd76cd5/filter/date=LAST_24H&extended=1%2C1%2CANR%2C0%2C0%2CTYPE%2Cnull/) | 1 | `anr-enabled` | 10.11.2026 20:07:35 |
| [ANR после pause/enable](https://apptracer.ru/24745424/crashes/report/ANR/73afcc99e3ccdb60fba31b50cb4b022b76f4f363e0b3ee3ae4af0ae39993ae85/11f1-dd29-7d0abf52-9adb-bb347c409873/filter/date=LAST_24H&extended=1%2C1%2CANR%2C0%2C0%2CTYPE%2Cnull/) | 1 | `resumed-anr-enabled` | 10.11.2026 20:09:21 |
| [Tombstone без native module](https://apptracer.ru/24745424/crashes/report/TOMBSTONE/f71286bea4bdc5aa50dacf7cd556e87a3bc7ef61cf16ed3f9109e6dd62f9396c/11f1-dd25-2eb2bc30-8747-d7646dd76cd5/filter/date=LAST_24H&extended=1%2C1%2CTOMBSTONE%2C0%2C0%2CTYPE%2Cnull/) | 1 | `native-enabled` | 10.11.2026 19:38:32 |

Дублей финальной серии не обнаружено: Java-группа выросла с 1 до 2 событий
(первый и финальный запуск), ANR — с 2 до 4 (два сценария в каждом запуске).
Оба финальных ANR проверены отдельно по userId/custom keys. Kotlin, native,
финальная Dart-группа и отдельный tombstone содержат по одному событию.
Идентификаторы/ссылки и точные поля сохранены в JSON.

Первая серия `sdk161-20261110` была диагностической: Kotlin/native в консоли
для неё не подтверждены, она не используется как доказательство полной доставки.
Её APK/buildUuid сохранены отдельно. Финальная серия доставила все шесть событий.
Native и Dart символизация здесь не сертифицируется; live upload native symbols
выключен. Проверка JVM-символизации не распространяется на native-кадры.

## Открытый дефект Kotlin-символизации

- Java подтверждён в консоли: `JavaCrashProbe.crash(JavaCrashProbe.java:6)`.
- Kotlin в консоли: `KotlinCrashProbe.crash(KotlinCrashProbe.java:14)`.
- Тот же raw frame `u0.b.a(SourceFile:14)` и точный загруженный mapping в
  **Retrace 8.9.32** дают `KotlinCrashProbe.crash(KotlinCrashProbe.kt:6)`.
- Расхождение есть в обоих режимах консоли: форматированный и обычный текст.
  Класс и метод восстановлены; исходный файл и строка — нет.

[Минимальный fixture](../tool/fixtures/android-sdk161/kotlin-symbolication/README.md)
содержит реальные mapping-записи и raw frames, Java-контроль и ожидаемый вывод.
Его Retrace повторно выполнен и побайтно сравнен с expected.txt. Полный mapping,
APK и загруженный payload связаны хешами; замена mapping/UUID и отсутствие
line/source metadata исключены. Исправление внешнего обработчика/отображения
Tracer отсутствует в этом репозитории. Проба оставлена обфусцируемой; изменение
ожидания на неправильную строку не используется как обход.

**Условие закрытия внешнего дефекта:** повторная проверка указанного Kotlin-отчёта после
исправления Tracer либо новая точная minified-сборка с доказанным исправлением:
консоль должна показывать исходные `.kt:6` вместе с восстановленными классом и
методом. До исправления сохранять ограничение в документации выпуска.
[№21 принят с исключением](tasks/development_completed_v1.md#task-android-21);
[внешний дефект остаётся открытым](tasks/development_android_1.6.1.md#blocker-kotlin-symbolication).

Независимый [блокер configuration cache полного Flutter assemble](tasks/development_android_1.6.1.md#blocker-flutter-configuration-cache)
также остаётся открытым; native fallback №19 не доказывает полный Flutter cache.

## Воспроизведение device-сценариев

Entrypoint: `example/lib/android_native_verification.dart`. После Flutter release
config собрать `:app:assembleConsentRelease` с `-Ptracer.enabled=true
-Ptracer.deferred=true`, соответствующими upload-флагами и `--no-configuration-cache`.
Не смешивать APK/mapping разных сборок. Явно выбрать disposable emulator:

```sh
adb -s "$SERIAL" shell am start \
  -n ru.apptracer.flutter.apptracer_flutter_example.consent/ru.apptracer.flutter.apptracer_flutter_example.MainActivity \
  --es apptracerScenario jvm-enabled --es apptracerRun sdk161-20261110-local
```

Между сценариями нужен новый процесс. `recovery` использует loopback,
`vendor-recovery` — Tracer. Не очищать данные приложения между падением и
recovery. `*-revoked` → `revoked-recovery` проверяет приоритет purge над preserve.
Состояния и синтетические loopback body/header сохраняются в app-specific
external files `verification`; credentials из этих файлов нельзя публиковать.
