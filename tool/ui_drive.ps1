# Weekend live-audit UI driver for the Android emulator.
# Thin wrappers over adb so the audit steps stay short and readable.
param(
  [Parameter(Position = 0)][string]$Action = 'dump',
  [string]$Target = '',
  [string]$Text = '',
  [string]$Out = "$env:TEMP\wk_shot.png"
)
$ErrorActionPreference = 'Continue'
$adb = "C:\Users\praka\AppData\Local\Android\Sdk\platform-tools\adb.exe"

switch ($Action) {
  'tap'    { $p = $Target -split ','; & $adb shell input tap $p[0] $p[1] }
  # `adb shell input text` treats a space as an argument separator, so a
  # multi-word value is silently truncated at the first space. %s is adb's own
  # escape for a literal space.
  'type'   { & $adb shell input text ($Text -replace ' ', '%s') }
  'key'    { & $adb shell input keyevent $Target }
  'swipe'  { $p = $Target -split ','; & $adb shell input swipe $p[0] $p[1] $p[2] $p[3] $p[4] }
  'back'   { & $adb shell input keyevent 4 }
  'shot'   {
    & $adb shell screencap -p /sdcard/_s.png | Out-Null
    & $adb pull /sdcard/_s.png $Out | Out-Null
    Write-Output "SHOT: $Out"
  }
  'dump'   {
    & $adb shell uiautomator dump /sdcard/_d.xml | Out-Null
    & $adb pull /sdcard/_d.xml "$env:TEMP\wk_dump.xml" | Out-Null
    Write-Output "DUMP: $env:TEMP\wk_dump.xml"
  }
  'find'   {
    # Print the text/content-desc/bounds of every node matching -Target.
    $xml = [xml](Get-Content "$env:TEMP\wk_dump.xml")
    $xml.SelectNodes('//node') | ForEach-Object {
      $t = $_.text; $d = $_.'content-desc'
      if ($t -match $Target -or $d -match $Target) {
        Write-Output ("text='{0}' desc='{1}' bounds={2} clickable={3}" -f $t, $d, $_.bounds, $_.clickable)
      }
    }
  }
  'logcat' { & $adb logcat -d -s flutter:* 2>&1 | Select-Object -Last 40 }
  default  { Write-Output 'actions: tap|type|key|swipe|back|shot|dump|find|logcat' }
}
