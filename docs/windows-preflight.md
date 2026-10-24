# Проверка отдельного Windows-компьютера

Подготовка к [№1 и №3](tasks/development_v1.md), 2026-10-23.
Первоначально пользователь планировал отдельный Windows-компьютер.
**Обновление 24 октября:** preflight и установка инструментов на D выполнены
на Windows 11 x64; [версии, результаты и границы](windows-local-acceptance.md).
Команды ниже сохранены для повторного запуска на другом компьютере.
Аврора пока недоступна и не требуется для этой проверки Windows.

## Инструменты

Установить Git, Flutter stable и Visual Studio с workload **Desktop development
with C++**, включая MSVC, Windows SDK и CMake tools. Visual Studio Code этот
workload не заменяет. Для первого прогона выбран Windows **x64**; если компьютер
ARM64, сначала уточнить отдельную матрицу SDK и backend.

Для сопоставимости с текущей macOS-средой предпочтителен Flutter **3.47.4**
(Dart **3.13.3**). Если установлена другая версия, сохранить её в отчёте;
успешный `pub get` не доказывает совместимость нативной сборки.

Официальные инструкции: [Flutter Windows setup](https://docs.flutter.dev/platform-integration/windows/setup),
[Microsoft: поиск VC toolset через vswhere](https://github.com/microsoft/vswhere/wiki/Find-VC).

## Отчёт среды

Открыть PowerShell в корне checkout `apptracer_flutter`. Выполнить блок целиком.
Отчёт сохраняется в игнорируемый Git каталог `build`; DSN и токены ему не нужны.
Он содержит пути установки инструментов — перед пересылкой можно убрать имя
пользователя из путей. Не добавлять в отчёт содержимое `.env.tracer`.

```powershell
$reportDir = Join-Path (Get-Location) 'build\windows-preflight'
New-Item -ItemType Directory -Force -Path $reportDir | Out-Null
$reportFile = Join-Path $reportDir ('environment-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.txt')
Start-Transcript -Path $reportFile
try {
    Get-Date -Format o
    Get-CimInstance Win32_OperatingSystem |
        Select-Object Caption, Version, BuildNumber, OSArchitecture |
        Format-List
    Get-CimInstance Win32_Processor |
        Select-Object Name, Architecture |
        Format-List
    git rev-parse HEAD
    git --version
    flutter --version
    flutter doctor -v
    flutter devices

    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (Test-Path $vswhere) {
        & $vswhere -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -format json
        $vsPath = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
        if ($vsPath) {
            $toolsetFile = Join-Path $vsPath 'VC\Auxiliary\Build\Microsoft.VCToolsVersion.default.txt'
            if (Test-Path $toolsetFile) {
                Write-Output 'Default MSVC toolset:'
                Get-Content $toolsetFile
            }
            $vsCmake = Join-Path $vsPath 'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'
            if (Test-Path $vsCmake) { & $vsCmake --version }
        } else {
            Write-Output 'MISSING: Visual Studio with x86/x64 C++ tools'
        }
    } else {
        Write-Output 'MISSING: Visual Studio Installer / vswhere'
    }
    $sdkRegistry = 'HKLM:\SOFTWARE\Microsoft\Windows Kits\Installed Roots'
    if (Test-Path $sdkRegistry) {
        $sdkRoot = (Get-ItemProperty $sdkRegistry).KitsRoot10
        if ($sdkRoot -and (Test-Path (Join-Path $sdkRoot 'Include'))) {
            Write-Output 'Installed Windows SDK include versions:'
            Get-ChildItem (Join-Path $sdkRoot 'Include') -Directory | Select-Object -ExpandProperty Name
        }
    }
} finally {
    Stop-Transcript
}
Write-Output $reportFile
```

Отчёт — инвентаризация, не автоматический pass/fail. Ошибки команд также нужно
сохранить. В `flutter doctor -v` должны пройти Windows и Visual Studio, а
`flutter devices` должен показать Windows target. Список установленных SDK не
определяет, какой SDK выберет CMake: фактическую версию записать из сборки №3.
Недостающие Android/iOS-инструменты сами по себе Windows-проверку не блокируют.

## Что остаётся после проверки среды

- Передать отчёт для фиксации реальных версий ОС/архитектуры и инструментов в №1.
- Получить `TRACER_WINDOWS_SENTRY_DSN` и `TRACER_WINDOWS_PLUGIN_TOKEN` из нужного
  проекта Tracer; хранить локально, не в отчёте и не в Git. Plugin token нужен
  только загрузчику символов.
- После реализации №2–3 проверить release runner, DLL/crash handler, запуск вне
  checkout, пути с пробелами/кириллицей, Dart/native события и повторный запуск.
  Windows runner теперь добавлен; см. [подготовку и команды](windows-preparation.md).
- Символизация и отзыв согласия — отдельные проверки №5/8/11; наличие компьютера
  и успешный `flutter doctor` их не закрывают.
