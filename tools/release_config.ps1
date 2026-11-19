# Shared by build_apk.ps1 and build_aab.ps1: finds tools\release-config.json
# and checks it holds Color Blendr's RevenueCat key. Dot-source it after
# Set-Location to the project root; it sets $config to the file's path.

$config = Join-Path (Get-Location) 'tools\release-config.json'
if (-not (Test-Path $config)) {
    throw 'Missing tools\release-config.json. Copy tools\release-config.example.json and put in the goog_ key from RevenueCat (Project -> API keys -> the Color Blendr Play Store app).'
}
$settings = Get-Content $config -Raw | ConvertFrom-Json
$key = [string]$settings.REVENUECAT_GOOGLE_KEY
if ($key -match 'X{6,}') { throw 'tools\release-config.json still has the placeholder key.' }
# A test_ key makes the RevenueCat SDK crash in release builds, on purpose.
if (-not $key.StartsWith('goog_')) { throw 'REVENUECAT_GOOGLE_KEY in tools\release-config.json must be the public goog_ key (not test_ or sk_).' }
