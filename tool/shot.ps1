# Capture a screenshot from the running emulator/device.
# Usage: powershell -File tool/shot.ps1 -Name profile-privacy -OutDir <dir>
param(
    [Parameter(Mandatory = $true)][string]$Name,
    [string]$OutDir = "$env:TEMP\opencode\shots"
)

$ErrorActionPreference = 'Stop'
$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
if (-not (Test-Path $adb)) { throw "adb not found at $adb" }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$remote = "/sdcard/$Name.png"
& $adb shell screencap -p $remote | Out-Null
if ($LASTEXITCODE -ne 0) { throw "screencap failed" }

$local = Join-Path $OutDir "$Name.png"
& $adb pull $remote $local | Out-Null
& $adb shell rm -f $remote | Out-Null

$len = (Get-Item $local).Length
"$local ($len bytes)"
if ($len -lt 20000) { "WARNING: unusually small capture - screen may still be loading" }
