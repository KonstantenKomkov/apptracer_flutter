# Build from any working directory without changing the user's Git settings.
[CmdletBinding()]
param(
    [string]$NativeDepsDirectory = '',
    [switch]$Obfuscate
)
$ErrorActionPreference = 'Stop'
$example = Join-Path $PSScriptRoot '../packages/apptracer_flutter_desktop/example'
if ([string]::IsNullOrEmpty($NativeDepsDirectory)) {
    $hash = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = $hash.ComputeHash([Text.Encoding]::UTF8.GetBytes((Resolve-Path $example).Path))
        $suffix = ([BitConverter]::ToString($bytes)).Replace('-', '').Substring(0, 12)
        $NativeDepsDirectory = Join-Path $env:TEMP "at-$suffix"
    } finally { $hash.Dispose() }
}
$countValue = [Environment]::GetEnvironmentVariable('GIT_CONFIG_COUNT', 'Process')
$count = if ([string]::IsNullOrEmpty($countValue)) { 0 } else { [int]$countValue }
if ($count -lt 0) { throw 'Invalid GIT_CONFIG_COUNT' }
$settings = @{
    GIT_CONFIG_COUNT = [string]($count + 1)
    "GIT_CONFIG_KEY_$count" = 'core.longpaths'
    "GIT_CONFIG_VALUE_$count" = 'true'
    APPTRACER_NATIVE_DEPS_DIR = [IO.Path]::GetFullPath($NativeDepsDirectory)
    SENTRY_NATIVE_BACKEND = 'native'
}
$previous = @{}
foreach ($key in $settings.Keys) {
    $previous[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
}
Push-Location $example
try {
    foreach ($key in $settings.Keys) {
        [Environment]::SetEnvironmentVariable($key, $settings[$key], 'Process')
    }
    & flutter pub get
    if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed: $LASTEXITCODE" }
    $buildArgs = @('build', 'windows', '--release')
    if ($Obfuscate) {
        $buildArgs += @('--obfuscate', '--split-debug-info=build/symbols/dart')
    }
    & flutter @buildArgs
    if ($LASTEXITCODE -ne 0) { throw "Windows release build failed: $LASTEXITCODE" }
} finally {
    foreach ($key in $settings.Keys) {
        [Environment]::SetEnvironmentVariable($key, $previous[$key], 'Process')
    }
    Pop-Location
}
