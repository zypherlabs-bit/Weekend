# Weekend - apply a migration file to the LIVE project via the Supabase
# Management API, statement by statement, inside one transaction.
#
# Reads the personal access token from %TEMP%\sbp_token.txt (outside the repo,
# never committed) or $env:SUPABASE_ACCESS_TOKEN. The token is never printed.
#
# Usage:
#   powershell -NoProfile -File tool\apply_one_migration.ps1 -File 022_advanced_search.sql
#
# Exits 0 on success, 1 on the first failing statement (the SQL and the error
# are both printed so the migration can be fixed and re-run).
param(
    [Parameter(Mandatory = $true)][string]$File,
    [string]$Ref = 'ocypgybqfushqfzisnvs'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$path = Join-Path $root "supabase\migrations\$File"
if (-not (Test-Path $path)) { throw "Migration not found: $path" }

$token = $env:SUPABASE_ACCESS_TOKEN
if ([string]::IsNullOrWhiteSpace($token)) {
    $tf = Join-Path $env:TEMP 'sbp_token.txt'
    if (-not (Test-Path $tf)) { throw "No Management API token." }
    $token = (Get-Content $tf -Raw).Trim()
}
$headers = @{ Authorization = "Bearer $token"; 'Content-Type' = 'application/json' }
$uri = "https://api.supabase.com/v1/projects/$Ref/database/query"

function Invoke-Db([string]$sql) {
    $json = @{ query = $sql } | ConvertTo-Json -Depth 3 -Compress
    $script:lastJson = $json
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    Invoke-RestMethod -Uri $uri -Method Post -Headers $headers `
        -ContentType 'application/json' -Body $bytes -TimeoutSec 180
}

# Split on top-level semicolons, respecting $$ ... $$, '...' and -- comments.
function Split-Sql([string]$script) {
    $out = New-Object System.Collections.Generic.List[string]
    $cur = New-Object System.Text.StringBuilder
    $inDollar = $false; $i = 0; $n = $script.Length
    while ($i -lt $n) {
        $c = $script[$i]
        if (-not $inDollar -and $c -eq '-' -and ($i + 1) -lt $n -and $script[$i + 1] -eq '-') {
            while ($i -lt $n -and $script[$i] -ne "`n") { $i++ }
            continue
        }
        if (-not $inDollar -and $c -eq "'") {
            [void]$cur.Append($c); $i++
            while ($i -lt $n) {
                [void]$cur.Append($script[$i])
                if ($script[$i] -eq "'") {
                    if (($i + 1) -lt $n -and $script[$i + 1] -eq "'") { [void]$cur.Append("'"); $i += 2; continue }
                    $i++; break
                }
                $i++
            }
            continue
        }
        if ($c -eq '$' -and ($i + 1) -lt $n -and $script[$i + 1] -eq '$') { $inDollar = -not $inDollar; [void]$cur.Append('$$'); $i += 2; continue }
        if (-not $inDollar -and $c -eq ';') { $s = $cur.ToString().Trim(); if ($s) { $out.Add($s) }; [void]$cur.Clear(); $i++; continue }
        [void]$cur.Append($c); $i++
    }
    $s = $cur.ToString().Trim()
    if ($s) { $out.Add($s) }
    return $out
}

$raw = Get-Content $path -Raw

# ---------------------------------------------------------------------------
# STRUCTURAL SELF-CHECK (runs BEFORE anything is sent).
#
# A truncated or spliced function body is the failure mode that silently
# swallows half a migration: statements 1..N apply, then one malformed
# function aborts the run and the database is left in a mixed state. Validate
# the whole file first so a bad edit never reaches the live project.
# ---------------------------------------------------------------------------
function Test-Structure([string]$raw) {
    $problems = @()
    $blocks = [regex]::Matches($raw, '(?s)\$\$(.*?)\$\$')
    foreach ($b in $blocks) {
        $body = $b.Groups[1].Value
        $beginCount = ([regex]::Matches($body, '(?im)^\s*begin\s*$')).Count
        $endCount = ([regex]::Matches($body, '(?im)^\s*end;\s*$')).Count
        if ($beginCount -gt 0 -and $beginCount -ne $endCount) {
            $problems += "begin=$beginCount end=$endCount (truncated plpgsql body)"
        }
        # `if ... then` may span several lines, so the condition is matched
        # across newlines up to the first `then`. A CASE expression also ends
        # in `then`, but it never *starts* a statement with `if`.
        $ifCount = ([regex]::Matches($body, '(?ims)^\s*if\b.*?\bthen\b')).Count
        $endIfCount = ([regex]::Matches($body, '(?im)^\s*end if;\s*$')).Count
        if ($ifCount -ne $endIfCount) {
            $problems += "if=$ifCount end-if=$endIfCount (truncated conditional)"
        }
        $head = ($body -replace '^\s+', '')
        if ($head -notmatch '^(begin|declare|select|--|/\*)') {
            $problems += "body does not begin with begin/declare/select"
        }
        if ($body -match '(?s)\bwhere\s*\r?\n\s*return query') {
            $problems += "'where' directly followed by 'return query' (spliced fragments)"
        }
    }
    $fnCount = ([regex]::Matches($raw, '(?im)^\s*create\s+(or\s+replace\s+)?function\s')).Count
    $closeCount = ([regex]::Matches($raw, '(?m)^\s*\$\$;\s*$')).Count
    if ($fnCount -ne $closeCount) {
        $problems += "$fnCount function(s) but $closeCount terminator(s)"
    }
    return $problems
}

$problems = Test-Structure $raw
if ($problems.Count -gt 0) {
    Write-Host "== STRUCTURE CHECK FAILED - nothing was sent to the database ==" -ForegroundColor Red
    foreach ($p in $problems) { Write-Host "   - $p" -ForegroundColor Red }
    exit 2
}
Write-Host "== STRUCTURE OK ==" -ForegroundColor Green

$stmts = Split-Sql $raw
Write-Host "== $File : $($stmts.Count) statements ==" -ForegroundColor Cyan

$n = 0
foreach ($s in $stmts) {
    $n++
    try {
        [void](Invoke-Db $s)
        Write-Host "  [$n/$($stmts.Count)] OK  $(($s -split "`n")[0].Trim().Substring(0, [Math]::Min(62, ($s -split "`n")[0].Trim().Length)))"
    } catch {
        Write-Host "  [$n/$($stmts.Count)] FAILED" -ForegroundColor Red
        Write-Host "----- statement -----"
        Write-Host $s
        Write-Host "----- error -----"
        # Invoke-RestMethod discards the response body on a 4xx, and the body is
        # the only place the actual Postgres error text lives. Re-send the same
        # payload through curl, which prints it verbatim.
        $tmp = Join-Path $env:TEMP "wkmig_err.json"
        [System.IO.File]::WriteAllText($tmp, ($script:lastJson), (New-Object System.Text.UTF8Encoding $false))
        & curl.exe -s -X POST $uri -H "Authorization: Bearer $token" `
            -H "Content-Type: application/json" --data-binary "@$tmp"
        Write-Host ""
        Remove-Item $tmp -ErrorAction SilentlyContinue
        exit 1
    }
}
Write-Host "== APPLIED OK ==" -ForegroundColor Green
