# apptracer_flutter_ios

Реализация [`apptracer_flutter`](https://github.com/KonstantenKomkov/apptracer_flutter) под iOS — неофициальной интеграции Flutter
с [Tracer](https://apptracer.ru).

> Не связан с VK и OK.TECH, не одобрен и не поддерживается ими.

English version: [README.en.md](README.en.md).

Зависеть от этого пакета напрямую не нужно: его подтягивает
`apptracer_flutter`.

## Что он делает

Передаёт ошибки Dart в SDK `OKTracer` как `TracerNonFatalModel`. Нативные
краши, зависания и отчёты MetricKit этот SDK обрабатывает сам.

Стектрейс Dart не несёт нативных адресов, а переданный массив символов Tracer
игнорирует, пока не подключён отладчик. Поэтому реализация синтезирует
`issueKey` из типа ошибки Dart и её верхнего кадра — так ошибки всё же
группируются по месту вызова. Передайте свой `issueKey`, чтобы это
переопределить.

Breadcrumbs доставляются через `TracerLogProviderProtocol`, который не трогает
настройки собственного логирования SDK.

## Подключение

Пакет поддерживает оба менеджера зависимостей Flutter для iOS: Swift Package
Manager и CocoaPods. Flutter выбирает тот, который включён в приложении.

### Swift Package Manager

Ничего настраивать не нужно: `Package.swift` объявляет `OKTracer`
зависимостью от [репозитория вендора](https://github.com/odnoklassniki/tracer-ios)
по версии, и Xcode забирает SDK сам. Нижняя граница — **1.5.2**: это первая
версия, бинарники которой лежат на `nexus-external.vkteam.ru`; прежний хост
вендор выключил 31.08.2026, и манифесты всех тегов до 1.5.2 ссылаются на него.
Если `Package.resolved` приложения ещё держит 1.5.1, разрешите зависимости
заново (File → Packages → Update to Latest Package Versions).

`Package.swift` не зависит ни от чего, что генерирует сам Flutter: `import
Flutter` резолвится через framework search paths, которые Flutter передаёт
сборке. Поэтому SPM-путь работает на любой версии, где SPM вообще есть, и
констрейнт пакета остаётся `>=3.22.0` для обоих путей. Так же устроены
`url_launcher_ios` из `flutter/packages` и `vkid_flutter_sdk`.

Единственное отличие от CocoaPods — фазу выгрузки `dSYM` придётся добавить
руками, потому что подспека, которая делает это при `pod install`, здесь никто
не выполняет. В Xcode: цель `Runner` → **Build Phases** → **+** → **New Run
Script Phase**, назовите её `[apptracer_flutter] Upload dSYMs to Tracer` и
вставьте содержимое
[`ios/tracer_dsym_upload_phase.sh`](ios/tracer_dsym_upload_phase.sh).

То же самое делает команда пакета — она сама находит скрипт и правит проект,
если в системе есть Ruby с gem `xcodeproj` (та же пара, на которой работает
CocoaPods):

```sh
dart run apptracer_flutter:install_ios_dsym_phase
```

Повторный запуск безопасен: существующая фаза обновляется на месте, а не
дублируется.

### CocoaPods

`OKTracer` лежит в собственном spec-репозитории вендора для CocoaPods и
поставляется статическим `xcframework`, поэтому в `ios/Podfile` нужны и
источник, и статическая линковка:

```ruby
source 'https://github.com/odnoklassniki/tracer-ios.git'
source 'https://cdn.cocoapods.org/'

platform :ios, '13.0'

target 'Runner' do
  use_frameworks! :linkage => :static
  # ...
end
```

Подспек и `Package.swift` фиксируют `OKTracer = 1.5.2` для проверенного
адаптера отзыва. Спеки всех версий до 1.5.1 включительно скачивают архив с выключенного
хоста. Если Tracer уже был подключён и `Podfile.lock` держит 1.5.1, `pod
install` остановится на «could not find compatible versions for pod OKTracer»
— выполните `pod update OKTracer`, он заодно обновит закешированный
spec-репозиторий вендора.

При `pod install` подспек добавляет в `Runner.xcodeproj` ту же фазу сборки,
которая отправляет `dSYM` при каждой release-сборке; `TRACER_SKIP_IOS_PHASE=1`
запрещает трогать файл проекта. Токен фаза берёт из
`ios/tracer_plugin_token` или из `TRACER_IOS_PLUGIN_TOKEN`.

В отличие от Android, `TracerOptions.appToken` на iOS **используется**.

## Native consent lifecycle

Use `TracerNativeInitialization.deferred` for bootstrap, then explicitly call
`Tracer.startCollection` after the application verifies consent. OKTracer is
pinned to **1.5.2**: the plugin audits and manages this version's report paths.

`stopAndClearCollection` (and `stopCollection`) stops and detaches the SDK, deletes pending
reports and replaces its report directories with empty guard files. This blocks
its surviving native crash writer from persisting new reports. Revocation is
saved before native stop, so an automatic startup in a new process stays off
with `consent_required`. After an active session the result is `restartRequired`;
start again only in a new process after new consent, with explicit deferred start.
That start purges old reports even when `preservePreviousReports` is requested.

A failed cleanup keeps collection off with `native_cleanup_failed`. Requests
already in flight may finish; reports already received by the server are not
deleted. The native crash handler itself remains installed until process exit.
The SDK storage paths are reserved for this plugin; do not run another OKTracer
service independently in the same process. Updating the pinned SDK requires a
new storage audit and the device acceptance tests.

See [implementation and device evidence](../../docs/native-collection-consent.md).

### Символы при сборке Xcode 27

На физическом iPhone проверена расшифровка Runner и Flutter с настройками
[`tracer_dwarf4.xcconfig`](ios/tracer_dwarf4.xcconfig). Для этой конфигурации
передайте абсолютный путь к файлу через `XCODE_XCCONFIG_FILE` при `flutter build ipa`.
Настройки действуют на всю сборку, включая Pods, сохраняют имена функций и строки,
но исключают отладочные типы импортированных Clang-модулей. Это явная настройка
сборки: установка пакета не меняет флаги чужого проекта. После сборки загрузите
dSYM до отправки новых сбоев. [Результат проверки](../../docs/symbolication.md).
