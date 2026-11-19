# Builds the Play Store bundle (obfuscated) with the RevenueCat key from
# tools\release-config.json and copies it to outputs\aab\ColorBlendr-v<version>.aab.
# Debug symbols for reading crash traces go to outputs\symbols\v<version>\
# (keep them for every release you upload).
# Bump the version in pubspec.yaml first: Play rejects a build number it has seen.
# Run from anywhere:  powershell -File tools\build_aab.ps1

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$line = Select-String -Path 'pubspec.yaml' -Pattern '^version:\s*([^+\s]+)' | Select-Object -First 1
if ($null -eq $line) { throw 'No version line found in pubspec.yaml' }
$version = $line.Matches[0].Groups[1].Value

. (Join-Path $PSScriptRoot 'release_config.ps1')
if (-not (Test-Path (Join-Path $root 'android\key.properties'))) { throw 'Missing android\key.properties: Play rejects debug-signed bundles.' }
if (-not (Select-String -Path 'android\local.properties' -Pattern '^admob\.appId=' -Quiet)) { throw 'Missing admob.appId in android\local.properties.' }

$symbols = Join-Path $root "outputs\symbols\v$version"
flutter build appbundle --release --obfuscate --split-debug-info="$symbols" --dart-define-from-file="$config"
if ($LASTEXITCODE -ne 0) { throw "flutter build appbundle failed ($LASTEXITCODE)" }

$outDir = Join-Path $root 'outputs\aab'
New-Item -ItemType Directory -Force $outDir | Out-Null
$dest = Join-Path $outDir "ColorBlendr-v$version.aab"
Copy-Item 'build\app\outputs\bundle\release\app-release.aab' $dest -Force
Write-Host "Bundle copied to $dest"
