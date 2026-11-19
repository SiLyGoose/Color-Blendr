# Builds a release APK with the RevenueCat key from tools\release-config.json
# and copies it to outputs\apk\ColorBlendr-v<version>.apk, taking the version
# from pubspec.yaml (the part before "+"). For installing on your own phone:
#   adb install -r outputs\apk\ColorBlendr-v<version>.apk
# Run from anywhere:  powershell -File tools\build_apk.ps1

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$line = Select-String -Path 'pubspec.yaml' -Pattern '^version:\s*([^+\s]+)' | Select-Object -First 1
if ($null -eq $line) { throw 'No version line found in pubspec.yaml' }
$version = $line.Matches[0].Groups[1].Value

. (Join-Path $PSScriptRoot 'release_config.ps1')

flutter build apk --release --dart-define-from-file="$config"
if ($LASTEXITCODE -ne 0) { throw "flutter build apk failed ($LASTEXITCODE)" }

$outDir = Join-Path $root 'outputs\apk'
New-Item -ItemType Directory -Force $outDir | Out-Null
$dest = Join-Path $outDir "ColorBlendr-v$version.apk"
Copy-Item 'build\app\outputs\flutter-apk\app-release.apk' $dest -Force
Write-Host "APK copied to $dest"
