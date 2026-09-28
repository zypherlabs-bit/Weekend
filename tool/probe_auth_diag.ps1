# Weekend - diagnostics for the live auth endpoints.
# Captures HTTP status + response body (never a token/password value) to
# $env:TEMP\wknd_auth_diag.txt for offline reading.
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
$root = Split-Path $PSScriptRoot -Parent
$vars = @{}
foreach ($line in Get-Content (Join-Path $root '.env')) {
    if ($line -notmatch '=') { continue }
    $p = $line -split '=', 2
    $vars[$p[0].Trim()] = $p[1].Trim()
}
$base = $vars['SUPABASE_URL']
$anon = $vars['SUPABASE_ANON_KEY']
$out = New-Object System.Collections.Generic.List[string]

function Probe([string]$label, [string]$method, [string]$uri, $body) {
    $h = @{ apikey = $anon; 'Content-Type' = 'application/json' }
    $p = @{ Uri = $uri; Method = $method; Headers = $h; UseBasicParsing = $true; TimeoutSec = 60 }
    if ($null -ne $body) {
        $p['Body'] = [System.Text.Encoding]::UTF8.GetBytes(($body | ConvertTo-Json -Depth 6 -Compress))
    }
    try {
        $r = Invoke-WebRequest @p
        $out.Add("$label -> HTTP $([int]$r.StatusCode)")
        foreach ($k in $r.Headers.AllKeys) {
            if ($k -match 'ratelimit|retry-after|x-supabase') { $out.Add("    $k : $($r.Headers[$k])") }
        }
    } catch {
        $code = 0; $bd = ''
        if ($_.Exception.Response) {
            $code = [int]$_.Exception.Response.StatusCode
            foreach ($k in $_.Exception.Response.Headers.AllKeys) {
                if ($k -match 'ratelimit|retry-after') { $out.Add("    $k : $($_.Exception.Response.Headers[$k])") }
            }
            try { $sr = New-Object IO.StreamReader($_.Exception.Response.GetResponseStream()); $bd = $sr.ReadToEnd() } catch {}
        }
        $out.Add("$label -> HTTP $code  body: $bd")
    }
}

# 1. Signup (expected 429 while the endpoint is throttled).
Probe 'SIGNUP' 'POST' "$base/auth/v1/signup" @{ email = ("probe." + [guid]::NewGuid().ToString('N') + "@example.com"); password = ('Wk!' + [guid]::NewGuid().ToString('N') + 'aA9') }

# 2. Password grant for the known-good account (proves the grant path works).
$bFile = Join-Path $env:TEMP 'wknd_b_email.txt'
$pFile = Join-Path $env:TEMP 'wknd_b_pw.txt'
if ((Test-Path $bFile) -and (Test-Path $pFile)) {
    Probe 'PASSWORD_GRANT_KNOWN_GOOD' 'POST' "$base/auth/v1/token?grant_type=password" `
        @{ email = (Get-Content $bFile -Raw).Trim(); password = (Get-Content $pFile -Raw).Trim() }
} else {
    $out.Add('PASSWORD_GRANT_KNOWN_GOOD -> skipped (no saved credentials)')
}

$dest = Join-Path $env:TEMP 'wknd_auth_diag.txt'
[System.IO.File]::WriteAllLines($dest, $out, (New-Object System.Text.UTF8Encoding $false))
Write-Host $out -join "`n"
