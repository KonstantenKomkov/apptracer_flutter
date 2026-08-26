# Questions for the Tracer team

Ask in [[Tracer] Feedback](https://t.me/tracer_feedback).

The list is deliberately short. Anything answerable from the published
artefacts, from the licence agreement, or by running the live-verification plan
has been removed — asking a vendor something you can check yourself wastes their
time and yours.

**Two questions to send now.** Two more are conditional and only get asked if a
specific check fails.

---

## Send now

Copy the block below as-is; it is written to be answerable without context.

---

Здравствуйте! Делаю открытый неофициальный Flutter-пакет-обёртку над вашими SDK
(`apptracer_flutter`). Пакет не распространяет ваши артефакты: на Android SDK
подключается как `compileOnly` и добавляется самим приложением, на iOS podspec
объявляет зависимость от `OKTracer` из вашего spec-репозитория. Каждый
пользователь пакета регистрируется у вас и принимает лицензионное соглашение
сам.

**1. Символы Dart (`--split-debug-info`).**

Flutter при сборке с `--obfuscate --split-debug-info` кладёт имена Dart-функций
в отдельный ELF-файл `app.android-arm64.symbols` с тем же GNU build-id, что и у
`libapp.so` в APK.

Проверил локально вашей же утилитой `dump_syms` из `tracer-plugin-1.4.0.jar`:

```
dump_syms app.android-arm64.symbols  -> MODULE Linux arm64 F99D...D70, 7545 FUNC с именами Dart
dump_syms libapp.so (stripped)       -> MODULE Linux arm64 F99D...D70, 0 FUNC
```

То есть модуль тот же, а символы есть только в первом файле. Отсюда вопросы:

По `ParsedSymbolFile.Quality` первый файл — `FULL`, второй — `CFI_ONLY`
(«No usable symbols found...»). В самом плагине есть сообщение: «If you're using
additionalLibrariesPath to provide symbol overrides for libraries packaged into
your application...» — то есть сценарий «положить лучшие символы для библиотеки,
упакованной в приложение», выглядит поддерживаемым. Отсюда вопросы:

- а) Я это сделал: положил файл в `additionalLibrariesPath` под именем
  `libapp.so` (чтобы совпали и имя модуля, и build-id) и включил
  `forceUploadNativeSymbols = true`. Загрузка проходит — плагин пишет
  `Uploading libapp.so:<build-id>` для всех трёх архитектур и сборка успешна;
  без принудительного флага он их пропускал, отвечая `Uploading them anyway due
  to forced upload` только с ним. Вопрос в другом: **применяются ли** эти
  символы к кадрам внутри `libapp.so` в нативных крашах и минидампах? Со
  стороны клиента этого не видно.
- б) В `ParsedSymbolFile` есть `originalLibHash` — хэш файла, из которого
  сгенерированы символы. У нас это файл символов Dart, а не настоящий
  `libapp.so`, поэтому хэш отличается. Сопоставление на бэкенде идёт по
  build-id или по этому хэшу? Если по хэшу — сценарий не сработает, и хотелось бы
  знать это заранее, а не по молчанию.
- в) Есть ли отдельный, «правильный» канал для debug-файлов Dart — например,
  Sentry-совместимый `debug-files upload` (chunk-upload API), если проект заведён
  с Sentry DSN?

Понимаю, что даже при положительном ответе это поможет только нативным крашам:
у ручного `TracerCrashReport.report` Dart-стектрейс — это текст, привязывать
символы не к чему.

Заодно мелочь: в том самом сообщении плагина опция названа
`dontWarnAboutLibraryConflicts`, а в `TracerConfig` и в документации она
`dontWarnOnLibraryConflicts`. Похоже на опечатку в тексте предупреждения.

**2. Публикация обёртки и наименование.**

Прочитал лицензионное соглашение (редакция от 29.05.2025). Пункты 4.2.1 и 4.2.3
пакет не задевает: элементы Библиотеки не воспроизводятся и не
распространяются, права не сублицензируются. Пункт 4.2.4 («использовать
Библиотеку как основу для продукта, содержащего такую же функциональность»)
читаю как запрет делать конкурирующий SDK, а не интеграционную обёртку, которая
без вашей Библиотеки не работает и данные шлёт в ваш же сервис.

Подтвердите, пожалуйста, что это чтение верное, и скажите, есть ли у вас
пожелания к наименованию — в соглашении пункта про товарный знак нет. Сейчас
пакет называется `apptracer_flutter`, в описании и README первой строкой
написано, что он неофициальный и к VK/OK.TECH отношения не имеет.

---

## Ask only if a check fails

### 3. Группировка NON_FATAL на iOS — если провалится проверка №10

По документации («Символизация и группировка сбоев») для нефатальных ошибок
группировка идёт именно по `issueKey`, если он задан. Обёртка на это и
рассчитывает: генерирует `dart/<Тип>/<метод>` — без файла и строки, чтобы ключ
не менялся при правках кода.

Спрашивать здесь нечего, пока проверка №10 не провалится. Если провалится —
значит, `issueKey` работает не так, как описано, и вопрос будет звучать так:
почему события с разными `issueKey` попали в одну группу (или наоборот)?
Приложить два `crashId` и оба `issueKey`.

### 4. Снят 26.08.2026 — DSN не нужен

Вопрос звучал «как получить DSN для web». Ответ выяснился сам: DSN нет ни у
одного проекта, и он не нужен. Распакованный с npm `@apptracer/sdk` 2.6.9 шлёт
события в собственный приём Tracer — `POST /api/crash/uploadBatch`, авторизуясь
`appToken`, — и пакет теперь делает то же самое. Формат снят перехватом живого
запроса и описан в [web-protocol.md](web-protocol.md); он принят живым сервером.

Если что-то и спрашивать по этому поводу, то не «как получить DSN», а вот это —
но только когда упрётся:

* Обязателен ли `POST /api/crash/trackSession` для приёма событий, или он нужен
  только для метрики crash-free?
* Как передать breadcrumbs? В SDK они уходят полем `logsFile` в base64, формат
  которого снять не удалось.

---

## What was removed, and why

| Вопрос | Почему снят |
|---|---|
| Ссылка на статический текст лицензии | Текст получен: страница рендерится на клиенте, `--headless --dump-dom` её отдаёт. Разбор — в [legal.md](legal.md). |
| Можно ли вообще публиковать обёртку | В основном отвечает само соглашение (см. [legal.md](legal.md)). Осталась одна неоднозначность по 4.2.4 — она вошла в вопрос 2. |
| Применяются ли native symbols к Dart-кадрам | Слилось с вопросом 1. |
| Поддерживается ли `additionalLibrariesPath` для `--split-debug-info` | Слилось с вопросом 1. |
| Sentry-совместимый `debug-files upload` | Слилось с вопросом 1, пункт «в». |
| Можно ли переопределить `appToken` в рантайме на Android | Ответ получен из байткода: `setOverrideAppToken` есть только на `CoreTracerConfiguration.Builder`, а он доступен лишь через `HasTracerConfiguration` в `Application`. Flutter-плагин туда не дотянется. Спрашивать нечего. |
| Как считается группировка и что на неё влияет | Описано в разделе «Символизация и группировка сбоев»: `crashId` из title и subtitle, файл и строка не учитываются, у нефатальных приоритет за `issueKey`. Разбор — в [platform-matrix.md](platform-matrix.md). |

---

## Where the answers go

| Ответ | Что меняет |
|---|---|
| 1 (а, б) положительный | `symbolication.md`, находка 2 → «подтверждено»; можно включать `prepare_dart_symbols.sh` в релизный пайплайн по умолчанию |
| 1 (а, б) отрицательный | убрать рекомендацию, оставить `flutter symbolize` единственным маршрутом |
| 1 (в) положительный | отдельная задача: автоматический загрузчик debug-файлов |
| 2 подтверждает чтение | публиковать; убрать раздел «residual ambiguity» из `legal.md` |
| 2 противоречит чтению | **не публиковать**, оставить внутренней интеграцией |
| 3 | поведение `apptracer_flutter_ios` и `platform-matrix.md` |
| 4 | `apptracer_flutter_http` и `platform-matrix.md` |

Ответы записывайте прямо сюда, под вопросом.
