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

Подспек требует `OKTracer >= 1.5.2` по той же причине, что и `Package.swift`
выше: спеки всех версий до 1.5.1 включительно скачивают архив с выключенного
хоста. Если Tracer уже был подключён и `Podfile.lock` держит 1.5.1, `pod
install` остановится на «could not find compatible versions for pod OKTracer»
— выполните `pod update OKTracer`, он заодно обновит закешированный
spec-репозиторий вендора.

При `pod install` подспек добавляет в `Runner.xcodeproj` ту же фазу сборки,
которая отправляет `dSYM` при каждой release-сборке; `TRACER_SKIP_IOS_PHASE=1`
запрещает трогать файл проекта. Токен фаза берёт из
`ios/tracer_plugin_token` или из `TRACER_IOS_PLUGIN_TOKEN`.

В отличие от Android, `TracerOptions.appToken` на iOS **используется**.
