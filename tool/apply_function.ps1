# Weekend - re-apply a single function definition from a migration file to the
# live project (used for hot-fixing SECURITY DEFINER RPCs without re-running
# whole migrations).
# Usage: powershell -File tool\apply_function.ps1 -Token sbp_... -File 006_security_fixes.sql -Function get_nearby_profiles
param(
    [Parameter(Mandatory = $true)][string]$Token,
    [Parameter(Mandatory = $true)][string]$File,
    [Parameter(Mandatory = $true)][string]$Function,
    [string]$Ref = 'ocypgybqfushqfzisnvs'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$sql = Get-Content (Join-Path $root "supabase\migrations\$File") -Raw -Encoding UTF8

# Match `create or replace function public.<name>(...) ... $$;` blocks.
$pattern = "(?s)create or replace function public\.$Function\s*\(.*?\$\$;"
$matchesFound = [regex]::Matches($sql, $pattern)
if ($matchesFound.Count -eq 0) {
    Write-Host "No definition found for $Function in $File" -ForegroundColor Red
    exit 1
}

$body = @{ query = $matchesFound[$matchesFound.Count - 1].Value } | ConvertTo-Json -Depth 2
$bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
try {
    Invoke-RestMethod `
        -Uri "https://api.supabase.com/v1/projects/$Ref/database/query" `
        -Method Post `
        -Headers @{ Authorization = "Bearer $Token" } `
        -ContentType 'application/json' `
        -Body $bytes `
        -TimeoutSec 180 | Out-Null
    Write-Host "OK: $Function applied from $File" -ForegroundColor Green
} catch {
    Write-Host "FAIL: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}