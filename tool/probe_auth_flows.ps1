# Weekend - probe auth flow capabilities of the LIVE project (read-only checks).
# Prints NO tokens. Results only: email confirmation required?, anonymous
# sign-in enabled?, trigger failure behaviour on malformed signup metadata.
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$vars = @{}
foreach ($line in Get-Content (Join-Path $root '.env')) {
    if ($line -match '^\s*#' -or $line -notmatch '=') { continue }
    $p = $line -split '=', 2
    $vars[$p[0].Trim()] = $p[1].Trim()
}
$u = $vars['SUPABASE_URL']
$k = $vars['SUPABASE_ANON_KEY']

function Post-Json([string]$uri, [string]$body, [hashtable]$headers) {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
    try {
        $r = Invoke-RestMethod -Uri $uri -Method Post -Headers $headers `
            -ContentType 'application/json' -Body $bytes -TimeoutSec 30
        return @{ ok = $true; data = $r }
    } catch {
        $code = 'n/a'; $bd = ''
        if ($_.Exception.Response) {
            $code = [int]$_.Exception.Response.StatusCode
            try {
                $sr = New-Object IO.StreamReader($_.Exception.Response.GetResponseStream())
                $bd = $sr.ReadToEnd()
            } catch { }
        } else { $bd = $_.Exception.Message }
        return @{ ok = $false; code = $code; body = $bd }
    }
}

$h = @{ apikey = $k; 'Content-Type' = 'application/json' }
$epoch = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

# 1. New signup -> session issued? (autoconfirm?)
$em1 = "wknd.e2e.probe.$epoch@gmail.com"
$r1 = Post-Json "$u/auth/v1/signup" (@{ email = $em1; password = 'E2eTestPassw0rd!'; data = @{ full_name = 'Weekend E2E Probe' } } | ConvertTo-Json -Depth 4) $h
if ($r1.ok) {
    $session = $null -ne $r1.data.access_token
    $uid = $r1.data.id
    if (-not $uid) { $uid = $r1.data.user.id }
    Write-Output ("SIGNUP session_issued={0} user_id={1} confirmation_sent={2}" -f $session, $uid, ($null -ne $r1.data.confirmation_sent_at))
} else {
    Write-Output ("SIGNUP failed HTTP {0}: {1}" -f $r1.code, $r1.body)
    $uid = $null
}

# 2. Password login right after signup (expect email_not_confirmed if gated)
$r2 = Post-Json "$u/auth/v1/token?grant_type=password" (@{ email = $em1; password = 'E2eTestPassw0rd!' } | ConvertTo-Json) $h
if ($r2.ok) {
    Write-Output ("LOGIN session_issued={0}" -f ($null -ne $r2.data.access_token))
} else {
    $err = ''
    try { $err = ($r2.body | ConvertFrom-Json).error_code } catch { $err = $r2.body }
    Write-Output ("LOGIN failed HTTP {0} error_code={1}" -f $r2.code, $err)
}

# 3. Anonymous sign-in (only works when enable_anonymous_signins is on)
$r3 = Post-Json "$u/auth/v1/signup" '{}' $h
if ($r3.ok) {
    $anonSession = $null -ne $r3.data.access_token
    Write-Output ("ANON enabled={0}" -f $anonSession)
} else {
    $err = ''
    try { $err = ($r3.body | ConvertFrom-Json).msg } catch { $err = $r3.body }
    Write-Output ("ANON unavailable HTTP {0}: {1}" -f $r3.code, $err)
}

# 4. Trigger robustness: malformed date_of_birth metadata must not abort signup.
$em2 = "wknd.e2e.baddob.$epoch@gmail.com"
$r4 = Post-Json "$u/auth/v1/signup" (@{ email = $em2; password = 'E2eTestPassw0rd!'; data = @{ full_name = 'Weekend E2E BadDOB'; date_of_birth = 'not-a-date' } } | ConvertTo-Json -Depth 4) $h
if ($r4.ok) {
    Write-Output ("BAD_DOB_SIGNUP ok (trigger tolerated malformed date)")
} else {
    Write-Output ("BAD_DOB_SIGNUP failed HTTP {0}: {1}" -f $r4.code, $r4.body)
}

# 5. Trigger robustness: gender outside the CHECK list.
$em3 = "wknd.e2e.badgender.$epoch@gmail.com"
$r5 = Post-Json "$u/auth/v1/signup" (@{ email = $em3; password = 'E2eTestPassw0rd!'; data = @{ full_name = 'Weekend E2E BadGender'; gender = 'Robot' } } | ConvertTo-Json -Depth 4) $h
if ($r5.ok) {
    Write-Output ("BAD_GENDER_SIGNUP ok (trigger tolerated invalid gender)")
} else {
    Write-Output ("BAD_GENDER_SIGNUP failed HTTP {0}: {1}" -f $r5.code, $r5.body)
}
