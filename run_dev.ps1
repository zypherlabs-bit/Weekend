# Weekend - run the app connected to your Supabase backend
#
# Reads SUPABASE_URL / SUPABASE_ANON_KEY from the .env file in the repo root
# (fill in .env first - see .env.example for hints).
#
#   .\run_dev.ps1           flutter run on the Android device/emulator
#   .\run_dev.ps1 -Chrome   flutter run -d chrome
#   .\run_dev.ps1 -Apk      flutter build apk --release (output in build\app\outputs)

param(
    [switch]$Apk,
    [switch]$Chrome
)

$ErrorActionPreference = 'Stop'
$root    = $PSScriptRoot
$envFile = Join-Path $root '.env'

if (-not (Test-Path $envFile)) {
    Write-Host 'No .env file found in the repo root.' -ForegroundColor Red
    Write-Host 'Create it (copy .env.example) and fill in SUPABASE_URL / SUPABASE_ANON_KEY.' -ForegroundColor Red
    exit 1
}

# Parse simple KEY=VALUE pairs; comments (#) and blanks are skipped.
$vars = @{}
Get-Content $envFile | ForEach-Object {
    $line = $_.Trim()
    if ($line -eq '' -or $line.StartsWith('#')) { return }
    $i = $line.IndexOf('=')
    if ($i -lt 1) { return }
    $vars[$line.Substring(0, $i).Trim()] = $line.Substring($i + 1).Trim()
}

$url = $vars['SUPABASE_URL']
$key = $vars['SUPABASE_ANON_KEY']

if (-not $url -or -not $key -or
    $url -like '*your-project-ref*' -or $key -eq 'public-anon-key-here') {
    Write-Host 'SUPABASE_URL / SUPABASE_ANON_KEY are missing or still placeholders in .env.' -ForegroundColor Red
    Write-Host 'Edit D:\Projects\Weekend\.env with real values from' -ForegroundColor Red
    Write-Host 'Supabase Dashboard -> Project Settings -> API, then re-run.' -ForegroundColor Red
    exit 1
}

$defines = @(
    "--dart-define=SUPABASE_URL=$url",
    "--dart-define=SUPABASE_ANON_KEY=$key"
)

if ($Apk) {
    Write-Host "Building release APK connected to: $url" -ForegroundColor Cyan
    flutter build apk --release @defines
} elseif ($Chrome) {
    Write-Host "Running in Chrome connected to: $url" -ForegroundColor Cyan
    flutter run -d chrome @defines
} else {
    Write-Host "Running on device/emulator connected to: $url" -ForegroundColor Cyan
    flutter run @defines
}
