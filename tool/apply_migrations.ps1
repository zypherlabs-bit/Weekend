# Weekend - apply Supabase migrations via the Management API.
# Usage: $env:SBP_TOKEN='sbp_...'; powershell -File tool\apply_migrations.ps1
# The token is read from the environment only; never written to disk.
param(
    [Parameter(Mandatory = $true)][string]$Token,
    [string]$Ref = 'ocypgybqfushqfzisnvs',
    # Optional migration file name prefix to start from (e.g. '002') after a
    # partially-applied earlier migration was completed manually.
    [string]$From = '',
    # Send each file as one transactional request instead of per-statement.
    [switch]$WholeFile
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent

Write-Host "== Applying migrations to project $Ref ==" -ForegroundColor Cyan

# Compatibility shim: the Management API SQL endpoint's parser rejects the
# `schema if not exists` clause on `create extension` (returns an opaque 400).
# On hosted Supabase PostGIS is preinstalled in the `extensions` schema, so
# dropping the clause is a safe no-op there and the type resolves via
# search_path anyway.
function Format-Sql([string]$input_) {
    return [regex]::Replace(
        $input_,
        '(?i)(create\s+extension\s+if\s+not\s+exists\s+(?:"[^"]+"|[\w]+))\s+schema\s+if\s+not\s+exists\s+\w+\s*;',
        '$1;')
}

# Split a SQL script into top-level statements, respecting $$ dollar-quoted
# bodies (function definitions), '...' strings and -- comments.
function Split-Statements([string]$script) {
    $stmts = New-Object System.Collections.Generic.List[string]
    $cur = New-Object System.Text.StringBuilder
    $inDollar = $false
    $i = 0; $n = $script.Length
    while ($i -lt $n) {
        $c = $script[$i]
        if (-not $inDollar -and $c -eq '-' -and $i + 1 -lt $n -and $script[$i+1] -eq '-') {
            # comment until end of line
            while ($i -lt $n -and $script[$i] -ne "`n") { [void]$cur.Append($script[$i]); $i++ }
            if ($i -lt $n) { [void]$cur.Append($script[$i]); $i++ }
            continue
        }
        if (-not $inDollar -and $c -eq "'") {
            # single-quoted string, consume with '' escapes
            [void]$cur.Append($script[$i]); $i++
            while ($i -lt $n) {
                [void]$cur.Append($script[$i])
                if ($script[$i] -eq "'") {
                    if ($i + 1 -lt $n -and $script[$i+1] -eq "'") { [void]$cur.Append("'"); $i += 2; continue }
                    $i++; break
                }
                $i++
            }
            continue
        }
        if ($c -eq '$' -and $i + 1 -lt $n -and $script[$i+1] -eq '$') {
            $inDollar = -not $inDollar
            [void]$cur.Append('$$'); $i += 2
            continue
        }
        if (-not $inDollar -and $c -eq ';') {
            $s = $cur.ToString().Trim()
            if ($s) { $stmts.Add($s) }
            [void]$cur.Clear()
            $i++
            continue
        }
        [void]$cur.Append($c)
        $i++
    }
    $s = $cur.ToString().Trim()
    if ($s) { $stmts.Add($s) }
    return $stmts
}

function Invoke-Query([string]$sql, [int]$maxAttempts = 4) {
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        $payload = @{ query = $sql } | ConvertTo-Json -Depth 2
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
        try {
            $r = Invoke-RestMethod `
                -Uri "https://api.supabase.com/v1/projects/$Ref/database/query" `
                -Method Post `
                -Headers @{ Authorization = "Bearer $Token" } `
                -ContentType 'application/json' `
                -Body $bytes `
                -TimeoutSec 180
            return @{ ok = $true; data = $r }
        } catch {
            $resp = $_.Exception.Response
            $code = if ($resp) { $resp.StatusCode.value__ } else { 0 }
            if ($code -eq 429 -and $attempt -lt $maxAttempts) {
                Write-Host '    rate-limited (429), waiting 15s...' -ForegroundColor Yellow
                Start-Sleep -Seconds 15
                continue
            }
            $bd = ''
            if ($resp) {
                try {
                    $sr = New-Object IO.StreamReader($resp.GetResponseStream())
                    $bd = $sr.ReadToEnd()
                } catch { }
            }
            return @{ ok = $false; code = $code; body = $bd }
        }
    }
}

# Apply a whole migration file in ONE transactional request. Falls back to
# statement-by-statement (with pacing) only when the whole-file request is
# rejected by the endpoint's SQL parser.
function Apply-File([string]$name, [string]$sql, [bool]$wholeFile) {
    if ($wholeFile) {
        $r = Invoke-Query $sql
        if ($r.ok) { Write-Host "  OK   $name (whole-file, transactional)" -ForegroundColor Green; return $true }
        Write-Host "  whole-file rejected (HTTP $($r.code)); falling back to per-statement" -ForegroundColor Yellow
    }
    $stmts = Split-Statements $sql
    Write-Host ("  {0}: {1} statements" -f $name, $stmts.Count) -ForegroundColor DarkCyan
    for ($i = 0; $i -lt $stmts.Count; $i++) {
        $s = $stmts[$i]
        Start-Sleep -Milliseconds 350
        $r = Invoke-Query $s
        if (-not $r.ok) {
            $preview = $s -replace '\s+', ' '
            if ($preview.Length -gt 90) { $preview = $preview.Substring(0, 90) + '...' }
            Write-Host ("    FAIL #{0}: {1}" -f $i, $preview) -ForegroundColor Red
            Write-Host ("      HTTP {0} {1}" -f $r.code, $r.body) -ForegroundColor Red
            return $false
        }
    }
    Write-Host "  OK   $name" -ForegroundColor Green
    return $true
}

$files = Get-ChildItem (Join-Path $root 'supabase\migrations') -Filter '*.sql' | Sort-Object Name
if ($From) { $files = $files | Where-Object { $_.Name -ge $From } }
foreach ($f in $files) {
    $sql = Format-Sql (Get-Content $f.FullName -Raw -Encoding UTF8)
    $ok = Apply-File -name $f.Name -sql $sql -wholeFile $WholeFile
    if (-not $ok) { Write-Host "  Stopped on $($f.Name)." -ForegroundColor Red; exit 1 }
}
Write-Host 'All migrations applied.' -ForegroundColor Green