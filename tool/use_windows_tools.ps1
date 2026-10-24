# Dot-source this file to keep Flutter, package caches and temporary builds on D.
[CmdletBinding()]
param([string]$ToolsDirectory = 'D:\Tools')
$ErrorActionPreference = 'Stop'
$toolsRoot = [IO.Path]::GetFullPath($ToolsDirectory)
$flutterBin = Join-Path $toolsRoot 'flutter/bin'
if (-not (Test-Path -LiteralPath (Join-Path $flutterBin 'flutter.bat'))) {
    throw "Flutter SDK not found in $flutterBin"
}
$env:PATH = "$flutterBin;$env:PATH"
$env:PUB_CACHE = Join-Path $toolsRoot 'PubCache'
$env:TEMP = Join-Path $toolsRoot 'Temp'
$env:TMP = $env:TEMP
New-Item -ItemType Directory -Force $env:PUB_CACHE,$env:TEMP | Out-Null
Write-Output "Flutter: $flutterBin; pub cache: $env:PUB_CACHE; temporary files: $env:TEMP"
