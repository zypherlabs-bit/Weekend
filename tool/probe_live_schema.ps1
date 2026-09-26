# Live schema probe: reports which migrations the LIVE Supabase project has.
# Uses the anon key from .env (public by design). Prints NO secret values.
$ErrorActionPreference = 'Stop'
$envFile = Join-Path $PSScriptRoot '..\.env'
$vars = @{}
foreach ($line in Get-Content $envFile) {
    if ($line -match '^\s*#' -or $line -notmatch '=') { continue }
    $p = $line -split '=', 2
    $vars[$p[0].Trim()] = $p[1].Trim()
}
$base = $vars['SUPABASE_URL']
$key  = $vars['SUPABASE_ANON_KEY']
if (-not $base -or -not $key) { Write-Output 'MISSING_CREDENTIALS'; exit 1 }
$headers = @{ apikey = $key; Authorization = "Bearer $key" }

function Probe([string]$label, [string]$path) {
    $uri = "$base/rest/v1/$path"
    try {
        $r = Invoke-WebRequest -Uri $uri -Headers $headers -UseBasicParsing -TimeoutSec 25
        Write-Output ("APPLIED   {0,-46} [{1}] {2}" -f $label, $r.StatusCode, $r.Content)
    } catch {
        $code = 'n/a'
        $body = ''
        if ($_.Exception.Response) {
            $code = [int]$_.Exception.Response.StatusCode
            try {
                $sr = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                $body = $sr.ReadToEnd()
            } catch { }
        } else { $body = $_.Exception.Message }
        Write-Output ("NOT-APPLIED {0,-44} [{1}] {2}" -f $label, $code, $body)
    }
}

Write-Output "=== LIVE schema probe: $base ==="
Probe '012 occupation/education/music/weekend' 'profiles?select=occupation,education,favorite_music,ideal_weekend&limit=1'
Probe '016 weekend_availability'                'user_settings?select=weekend_availability&limit=1'
Probe '016 location toggles'                    'user_settings?select=location_discovery_enabled,nearby_discovery_enabled,show_distance_enabled,travel_mode_enabled,crossed_paths_enabled&limit=1'
Probe '016 read_receipts_enabled'               'user_settings?select=read_receipts_enabled&limit=1'
Probe '016 referral_code (005)'                 'profiles?select=referral_code&limit=1'
Probe 'probe interests table (002/018)'         'interests?select=name&limit=1'
Probe 'probe user_interests table'              'user_interests?select=user_id&limit=1'
Probe 'probe profile_photos table'              'profile_photos?select=storage_path,moderation_status&limit=1'
Write-Output '=== probe complete ==='
