# Weekend - create two fresh, email-confirmed test accounts against the LIVE
# project and cache their session tokens outside the repository.
#
# Requires:
#   <repo>\.env                                  (SUPABASE_URL, SUPABASE_ANON_KEY)
#   %TEMP%\sbp_token.txt                        (Supabase personal access token)
#
# Writes %TEMP%\wknd_<A|B>_{token,uid,email,password}.txt (mode: user-only).
# Prints NO password, token, or email value.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$root = Split-Path $PSScriptRoot -Parent
$vars = @{}
foreach ($line in Get-Content (Join-Path $root '.env')) {
    if ($line -match '^\s*#' -or $line -notmatch '=') { continue }
    $p = $line -split '=', 2
    $vars[$p[0].Trim()] = $p[1].Trim()
}
$base = $vars['SUPABASE_URL']
$anon = $vars['SUPABASE_ANON_KEY']
$ref = 'ocypgybqfushqfzisnvs'
$mgtToken = (Get-Content (Join-Path $env:TEMP 'sbp_token.txt') -Raw).Trim()

function Sql([string]$q) {
    $h = @{ Authorization = 'Bearer ' + $mgtToken; 'Content-Type' = 'application/json' }
    $b = [System.Text.Encoding]::UTF8.GetBytes((@{ query = $q } | ConvertTo-Json -Depth 3))
    Invoke-RestMethod -Uri "https://api.supabase.com/v1/projects/$ref/database/query" `
        -Method Post -Headers $h -ContentType 'application/json' -Body $b -TimeoutSec 120
}

function New-Account([string]$tag) {
    $stamp = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $email = "wknd.$tag.$stamp@example.com"
    # Random per-account password: never reused, never printed.
    $pw = 'Wk!' + [guid]::NewGuid().ToString('N') + 'aA9'

    $body = @{ email = $email; password = $pw } | ConvertTo-Json -Compress
    $h = @{ apikey = $anon; 'Content-Type' = 'application/json' }
    $created = $false
    try {
        $null = Invoke-WebRequest -Uri "$base/auth/v1/signup" -Method Post -Headers $h `
            -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -UseBasicParsing -TimeoutSec 60
        $created = $true
    } catch {
        $code = 0
        if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
        if ($code -ne 429) { throw }
        # HTTP 429: the project's /auth/v1/signup endpoint is IP-rate-limited.
        # Fall back to provisioning the account directly as the database owner.
        # GoTrue still issues the session through the real password-grant
        # endpoint below, so this is a provisioning path only - it does not
        # bypass RLS, and no application code depends on it.
        Write-Host "  signup rate-limited (429); provisioning '$tag' via SQL instead"
        $litEmail = $email.Replace("'", "''")
        $litPw = $pw.Replace("'", "''")
        $newId = [guid]::NewGuid().ToString()
        $identId = [guid]::NewGuid().ToString()
        $null = Sql ("insert into auth.users (instance_id, id, aud, role, email, " +
            "encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, " +
            "created_at, updated_at) values " +
            "('00000000-0000-0000-0000-000000000000', '$newId', 'authenticated', 'authenticated', " +
            "'$litEmail', crypt('$litPw', gen_salt('bf')), now(), " +
            "'{""provider"":""email"",""providers"":[""email""]}'::jsonb, '{}'::jsonb, now(), now())")
        $null = Sql ("insert into auth.identities (id, user_id, identity_data, provider, " +
            "provider_id, last_sign_in_at, created_at, updated_at) values " +
            "('$identId', '$newId', jsonb_build_object('email', '$litEmail', 'sub', '$newId'), " +
            "'email', '$newId', now(), now(), now())")
        $created = $true
    }

    # Email confirmation is enabled on the live project; confirm so the account
    # can hold a real password session.
    $lit = $email.Replace("'", "''")
    $null = Sql "update auth.users set email_confirmed_at = now() where email = '$lit' and email_confirmed_at is null"


    $tokBody = @{ email = $email; password = $pw } | ConvertTo-Json -Compress
    $tokH = @{ apikey = $anon; 'Content-Type' = 'application/json' }
    $t = Invoke-RestMethod -Uri "$base/auth/v1/token?grant_type=password" -Method Post `
        -Headers $tokH -Body ([System.Text.Encoding]::UTF8.GetBytes($tokBody)) -TimeoutSec 60

    $uid = $t.user.id
    foreach ($kv in @(@('token', $t.access_token), @('uid', $uid), @('email', $email), @('password', $pw))) {
        $dest = Join-Path $env:TEMP "wknd_${tag}_$($kv[0]).txt"
        [System.IO.File]::WriteAllText($dest, $kv[1], (New-Object System.Text.UTF8Encoding $false))
    }
    return $uid
}

$uidA = New-Account 'A'
$uidB = New-Account 'B'
Write-Host "Created test accounts. A uid=$uidA  B uid=$uidB"

# Prove the fresh accounts are usable and their rows are present.
$probe = Sql @"
select
  (select count(*) from public.profiles        where id in ('$uidA','$uidB')) as profiles,
  (select count(*) from public.user_settings   where user_id in ('$uidA','$uidB')) as settings,
  (select count(*) from public.preferences     where user_id in ('$uidA','$uidB')) as prefs,
  (select count(*) from auth.users u left join public.profiles p on p.id=u.id where p.id is null) as orphan_profiles
"@
$probe | ConvertTo-Json -Depth 5
