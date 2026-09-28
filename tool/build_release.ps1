# Weekend - build the RELEASE APK against the LIVE Supabase project.
#
# Reads SUPABASE_URL / SUPABASE_ANON_KEY from the git-ignored .env and passes
# them as --dart-define so the binary is a genuine LIVE build.
#
# The anon key is a *public* client key (it ships inside every APK by design);
# it is never printed here. No service-role or secret key is passed - by design
# the Android client must not contain one.
param([switch]$Clean)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root
$vars = @{}
foreach ($line in Get-Content (Join-Path $root '.env')) {
    if ($line -notmatch '=') { continue }
    $p = $line -split '=', 2
    $vars[$p[0].Trim()] = $p[1].Trim()
}
$url = $vars['SUPABASE_URL']; $anon = $vars['SUPABASE_ANON_KEY']
if (-not $url -or -not $anon) { throw 'SUPABASE_URL / SUPABASE_ANON_KEY missing from .env' }
if ($url -match 'your-project-ref' -or $anon -eq 'public-anon-key-here') {
    throw 'Refusing to build: .env still holds placeholder credentials.'
}
if ($anon -match 'service_role') { throw 'Refusing to build: .env contains a service-role key.' }

if ($Clean) { Write-Host '=== flutter clean ==='; flutter clean | Out-Host }

Write-Host '=== flutter pub get ==='
flutter pub get | Out-Host

Write-Host '=== flutter build apk --release (LIVE) ==='
flutter build apk --release `
    --dart-define="SUPABASE_URL=$url" `
    --dart-define="SUPABASE_ANON_KEY=$anon" | Out-Host

$apk = Join-Path $root 'build\app\outputs\flutter-apk\app-release.apk'
if (-not (Test-Path $apk)) { throw "APK not produced at $apk" }
$hash = (Get-FileHash -Algorithm SHA256 -Path $apk).Hash.ToLower()
Write-Host "APK: $apk"
Write-Host "SIZE: $((Get-Item $apk).Length) bytes"
Write-Host "SHA256: $hash"

# Record the local hash so tests/python/test_release.py can compare the built
# artefact against whatever GitHub actually serves. Recorded here rather than
# only printed, because a hash nobody can read back proves nothing.
$releaseDir = Join-Path $root 'build\release'
New-Item -ItemType Directory -Force -Path $releaseDir | Out-Null
$hashLine = "$hash  app-release.apk"
Set-Content -Path (Join-Path $releaseDir 'apk.sha256') -Value $hashLine -Encoding ascii
Write-Host "Recorded: build\release\apk.sha256"
