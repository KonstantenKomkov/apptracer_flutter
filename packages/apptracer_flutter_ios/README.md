# apptracer_flutter_ios

Реализация [`apptracer_flutter`](https://github.com/komkovkonstantin/apptracer_flutter) под iOS — неофициальной интеграции Flutter
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

`OKTracer` лежит в собственном spec-репозитории вендора для CocoaPods, поэтому
его надо объявить в `ios/Podfile`:

```ruby
source 'https://github.com/odnoklassniki/tracer-ios.git'
source 'https://cdn.cocoapods.org/'

platform :ios, '13.0'
```

В отличие от Android, `TracerOptions.appToken` на iOS **используется**.
