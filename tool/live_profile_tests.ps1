# Weekend - live REST tests for the Edit Profile save path.
#
# Requires (outside the repository):
#   %TEMP%\wknd_A_token.txt / wknd_A_uid.txt  - user A session (password grant)
#   %TEMP%\wknd_B_token.txt / wknd_B_uid.txt  - user B session (password grant)
# Reads the anon client credentials from the repository's gitignored .env.
#
# Prints PASS/FAIL per test, HTTP status codes and non-sensitive row values.
# NEVER prints a token, an email, an access/refresh token or a GPS value.
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

$tokA = (Get-Content "$env:TEMP\wknd_A_token.txt" -Raw).Trim()
$uidA = (Get-Content "$env:TEMP\wknd_A_uid.txt" -Raw).Trim()
$tokB = (Get-Content "$env:TEMP\wknd_B_token.txt" -Raw).Trim()
$uidB = (Get-Content "$env:TEMP\wknd_B_uid.txt" -Raw).Trim()

$script:pass = 0
$script:fail = 0

function Result([string]$name, [bool]$ok, [string]$detail) {
    if ($ok) { $script:pass++; Write-Output ("PASS  {0}  [{1}]" -f $name, $detail) }
    else { $script:fail++; Write-Output ("FAIL  {0}  [{1}]" -f $name, $detail) }
}

# Rest call with a user's JWT. Returns @{ status; body }
#
# IMPORTANT (mirrors supabase-dart exactly): mutations must carry a
# `select=id` filter and `Prefer: return=representation`. Without the
# `select` filter PostgREST returns the WHOLE row, and since migration 006
# revoked table-level SELECT on `profiles` (column grants only) that request
# fails with 42501 "permission denied" — an artifact of the request shape,
# not of RLS. The shipped client always does `.update(...).select('id')`.
function Rest([string]$method, [string]$table, [string]$query, $body, [string]$token) {
    $uri = "$base/rest/v1/$table" + $(if ($query) { "?$query" } else { '' })
    $h = @{
        apikey        = $anon
        Authorization = "Bearer $token"
    }
    if ($query -match 'on_conflict=') {
        $h['Prefer'] = 'resolution=merge-duplicates, return=representation'
    } elseif ($query -match 'select=') {
        $h['Prefer'] = 'return=representation'
    }
    $params = @{
        Uri             = $uri
        Method          = $method
        Headers         = $h
        TimeoutSec      = 30
        UseBasicParsing = $true
    }
    if ($null -ne $body) {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes(($body | ConvertTo-Json -Depth 6 -Compress))
        $params['Body'] = $bytes
        $params['ContentType'] = 'application/json'
    }
    try {
        $r = Invoke-WebRequest @params
        $content = $r.Content
        if ($content -is [byte[]]) { $content = [System.Text.Encoding]::UTF8.GetString($content) }
        return @{ status = [int]$r.StatusCode; body = $content }
    } catch {
        $code = 'n/a'; $bd = ''
        if ($_.Exception.Response) {
            $code = [int]$_.Exception.Response.StatusCode
            try { $sr = New-Object IO.StreamReader($_.Exception.Response.GetResponseStream()); $bd = $sr.ReadToEnd() } catch { }
        } else { $bd = $_.Exception.Message }
        return @{ status = $code; body = $bd }
    }
}

function FirstRow($r) {
    if ($r.status -eq 200 -and $r.body -ne '[]') { return ($r.body | ConvertFrom-Json)[0] }
    return $null
}

Write-Output "=== Weekend live profile-save tests (public client key + user JWTs) ==="

# --- T1: the profile row exists for A (signup trigger; Test 13) --------------
$r = Rest 'GET' 'profiles' 'select=id,display_name,gender,relationship_intent,date_of_birth&limit=1' $null $tokA
Result 'T1 own profile row readable (RLS SELECT own)' ($r.status -eq 200 -and $r.body -ne '[]') "HTTP $($r.status)"

# --- T2: UPDATE every editable field (Test 1 / Test 7) -----------------------
$stamp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$payload = @{
    display_name        = "E2E Ada $stamp"
    bio                 = 'I enjoy music, travel, food and relaxed weekends.'
    city                = 'E2E City'
    gender              = 'Non-binary'
    relationship_intent = 'New people & Friendships'
    occupation          = 'E2E Occupation'
    education           = 'E2E Education'
    favorite_music      = 'E2E Jazz'
    ideal_weekend       = 'E2E Hiking'
}
$r = Rest 'PATCH' 'profiles' "id=eq.$uidA&select=id" $payload $tokA
Result 'T2 UPDATE all 9 fields returns a row' ($r.status -eq 200) "HTTP $($r.status) body=$($r.body.Substring(0, [Math]::Min(80, $r.body.Length)))"

# --- T3: fresh SELECT equals what was sent (Test 12) -------------------------
$r = Rest 'GET' 'profiles' "select=display_name,bio,city,gender,relationship_intent,occupation,education,favorite_music,ideal_weekend&id=eq.$uidA" $null $tokA
$row = FirstRow $r
$allMatch = $row -ne $null -and
    $row.display_name -eq $payload.display_name -and
    $row.bio -eq $payload.bio -and
    $row.city -eq $payload.city -and
    $row.gender -eq $payload.gender -and
    $row.relationship_intent -eq $payload.relationship_intent -and
    $row.occupation -eq $payload.occupation -and
    $row.education -eq $payload.education -and
    $row.favorite_music -eq $payload.favorite_music -and
    $row.ideal_weekend -eq $payload.ideal_weekend
Result 'T3 fresh SELECT returns the persisted values' $allMatch "HTTP $($r.status) name=$($row.display_name) city=$($row.city)"

# --- T4: blocked bio rejected (Test 4) ---------------------------------------
$bad = @{ bio = 'Find me on Instagram @weekend_fan or https://instagram.com/weekend_fan' }
$r = Rest 'PATCH' 'profiles' "id=eq.$uidA&select=id" $bad $tokA
$rejected = ($r.status -ge 400) -or ($r.body -eq '[]')
Result 'T4 blocked social-media bio rejected' $rejected "HTTP $($r.status) body=$($r.body.Substring(0, [Math]::Min(110, $r.body.Length)))"

$r2 = Rest 'GET' 'profiles' "select=bio&id=eq.$uidA" $null $tokA
$row2 = FirstRow $r2
Result 'T4b database bio unchanged after rejection' ($row2 -ne $null -and $row2.bio -eq $payload.bio) "bio unchanged=$($row2.bio -eq $payload.bio)"

# --- T5: valid bio saves (Test 5) -------------------------------------------
$good = @{ bio = 'I love hiking, movies and weekend trips.' }
$r = Rest 'PATCH' 'profiles' "id=eq.$uidA&select=id" $good $tokA
$r2 = Rest 'GET' 'profiles' "select=bio&id=eq.$uidA" $null $tokA
$row2 = FirstRow $r2
Result 'T5 valid bio saves and persists' ($r.status -eq 200 -and $row2 -ne $null -and $row2.bio -eq $good.bio) "HTTP $($r.status) persisted=$($row2.bio -eq $good.bio)"

# --- T6: 014 detection RPC (policy surface) ----------------------------------
$r = Rest 'POST' 'rpc/detect_social_media_in_text' '' @{ p_text = 'follow me on instagram' } $tokA
$det1 = $false; if ($r.status -eq 200) { $det1 = ($r.body | ConvertFrom-Json).detected -eq $true }
Result 'T6a RPC detects blocked content' $det1 "HTTP $($r.status)"
$r = Rest 'POST' 'rpc/detect_social_media_in_text' '' @{ p_text = 'I love hiking, movies and weekend trips.' } $tokA
$det2 = $false; if ($r.status -eq 200) { $det2 = ($r.body | ConvertFrom-Json).detected -eq $false }
Result 'T6b RPC passes clean content' $det2 "HTTP $($r.status)"

# --- T7: user A cannot update user B (Test 10) -------------------------------
$r = Rest 'PATCH' 'profiles' "id=eq.$uidB&select=id" @{ display_name = 'HIJACKED BY A' } $tokA
$noWrite = ($r.status -eq 200 -and $r.body -eq '[]') -or ($r.status -ge 400)
Result 'T7 A cannot UPDATE B (RLS)' $noWrite "HTTP $($r.status) body=$($r.body.Substring(0, [Math]::Min(80, $r.body.Length)))"

# --- T8: user A cannot insert a profile as user B (Test 11) ------------------
$r = Rest 'POST' 'profiles' 'select=id' @{ id = $uidB; display_name = 'FORGED BY A' } $tokA
$denied = ($r.status -ge 400) -and ($r.body -match 'row-level security|42501|new row violates')
Result 'T8 A cannot INSERT profile owned by B' $denied "HTTP $($r.status) body=$($r.body.Substring(0, [Math]::Min(110, $r.body.Length)))"

# --- T9: user A cannot delete their own profile (no DELETE policy) -----------
# PostgREST answers a DELETE that RLS filters out with 204 (nothing deleted) or
# 200 []; anything else would mean a row went away.
$r = Rest 'DELETE' 'profiles' "id=eq.$uidA" $null $tokA
$noDelete = ($r.status -eq 204) -or ($r.status -eq 200 -and $r.body -eq '[]') -or ($r.status -ge 400)
$stillThere = $false
$rCheck = Rest 'GET' 'profiles' "select=id&id=eq.$uidA" $null $tokA
if ($rCheck.status -eq 200 -and $rCheck.body -ne '[]') { $stillThere = $true }
Result 'T9 A cannot DELETE own profile (row still exists)' ($noDelete -and $stillThere) "HTTP $($r.status), row_present=$stillThere"

# --- T10: B can save B, and B cannot touch A (Test 10) ----------------------
$r = Rest 'PATCH' 'profiles' "id=eq.$uidB&select=id" @{ display_name = 'E2E Bob' } $tokB
Result 'T10a B can UPDATE own profile' ($r.status -eq 200) "HTTP $($r.status)"
$r = Rest 'PATCH' 'profiles' "id=eq.$uidA&select=id" @{ display_name = 'HIJACKED BY B' } $tokB
$t10b = ($r.status -eq 200 -and $r.body -eq '[]') -or ($r.status -ge 400)
Result 'T10b B cannot UPDATE A (RLS)' $t10b "HTTP $($r.status) body=$($r.body.Substring(0, [Math]::Min(80, $r.body.Length)))"

# --- T11: companion rows (user_settings upsert, as the client does) ----------
$r = Rest 'POST' 'user_settings' 'on_conflict=user_id&select=user_id' @{ user_id = $uidA; weekend_availability = @{ Saturday = $true; Sunday = $false } } $tokA
Result 'T11 user_settings upsert (weekend availability) accepted' ($r.status -ge 200 -and $r.status -lt 300) "HTTP $($r.status) body=$($r.body.Substring(0, [Math]::Min(90, $r.body.Length)))"

# --- T12: preferences row for own account (Test 3 restore path) -------------
$r = Rest 'GET' 'preferences' "select=user_id&user_id=eq.$uidA" $null $tokA
Result 'T12 own preferences row readable' ($r.status -eq 200) "HTTP $($r.status) body=$($r.body.Substring(0, [Math]::Min(60, $r.body.Length)))"

Write-Output ("=== summary: {0} pass, {1} fail ===" -f $script:pass, $script:fail)
if ($script:fail -gt 0) { exit 1 }
