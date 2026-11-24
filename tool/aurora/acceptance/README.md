# Проверка нативного отчёта из песочницы Авроры

Тестовый RPM носит тот же app ID, что и пример плагина. Используйте отдельную
установку примера на эмуляторе. ADT при повторном развёртывании может удалить
данные предыдущей установки.

Подготовьте SDK по [инструкции пакета](../../../aurora/apptracer_flutter_aurora/README.md).
Из корня репозитория соберите тест с помощью Flutter Аврора. Параметр
`--sdk-dir` нужен при отдельной установке Build Tools. Скрипт сначала генерирует
runner средствами ОМП, затем собирает тестовую точку входа в новом каталоге
под `build/`. В конце Flutter выведет путь к подписанному RPM.

```sh
export AURORA_FLUTTER_BIN=/path/to/flutter_aurora/bin/flutter
tool/aurora/acceptance/build.sh --sdk-dir /path/to/AuroraSDK
adt device deploy --silent /path/to/test.rpm
```

Явно разрешите тестовый сбой и отправку двумя запусками. Каждая команда
запрашивает app token со скрытым вводом или читает `TRACER_AURORA_APP_TOKEN`
из окружения. Значение передаётся по SSH во временный файл с закрытыми правами.
Приложение считывает и удаляет его перед запуском рабочего процесса.
Параметры SSH ниже соответствуют локальному экземпляру эмулятора.

```sh
emu="$HOME/AuroraEmulator-5.2.1.200"
python3 tool/aurora/acceptance/run.py arm -- -p 2223 -i "$emu/ssh/id_rsa" \
  -o "UserKnownHostsFile=$emu/ssh/known_hosts" defaultuser@127.0.0.1
python3 tool/aurora/acceptance/run.py upload -- -p 2223 -i "$emu/ssh/id_rsa" \
  -o "UserKnownHostsFile=$emu/ssh/known_hosts" defaultuser@127.0.0.1
```

При первом запуске предоставьте запрошенное ОС разрешение на сеть. В режиме
`arm` процесс SDK записывает ключ и лог, затем завершается. Flutter runner
вызывает SIGABRT. На следующем запуске дочерний процесс импортирует системный
минидамп до инициализации новой сессии SDK и вызывает `tracer_upload`.

В кабинете проверьте NATIVE для версии `2.0.0 (201)`, ключ
`aurora_runner=flutter-sandbox` и лог «Контрольное падение Flutter runner
в песочнице Авроры». Тест рассчитан на одно падение между двумя командами.
У штатного примера инициализация SDK и отправка выключены.
