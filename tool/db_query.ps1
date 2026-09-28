# Weekend - run one SQL statement against the LIVE project via the Supabase
# Management API. Requires the personal access token in %TEMP%\sbp_token.txt
# (outside the repository; never committed). Prints the raw JSON result or an
# error; prints NO token values.
#
# -OutFile <path> writes the result as UTF-8 so callers can read it back
# reliably regardless of the host console's code page.
param(
    [Parameter(Mandatory = $true)][string]$Sql,
    [string]$Ref = 'ocypgybqfushqfzisnvs',
    [string]$OutFile
)
$ErrorActionPreference = 'Stop'
$token = (Get-Content (Join-Path $env:TEMP 'sbp_token.txt') -Raw).Trim()
$h = @{ Authorization = "Bearer $token"; 'Content-Type' = 'application/json' }
$payload = @{ query = $Sql } | ConvertTo-Json -Depth 3
$bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
$text = $null
try {
    $r = Invoke-RestMethod -Uri "https://api.supabase.com/v1/projects/$Ref/database/query" `
        -Method Post -Headers $h -ContentType 'application/json' `
        -Body $bytes -TimeoutSec 120
    $text = $r | ConvertTo-Json -Depth 8 -Compress
} catch {
    $code = 'n/a'; $bd = ''
    if ($_.Exception.Response) {
        $code = [int]$_.Exception.Response.StatusCode
        try {
            $sr = New-Object IO.StreamReader($_.Exception.Response.GetResponseStream())
            $bd = $sr.ReadToEnd()
        } catch { }
    }
    $text = ("ERROR HTTP {0}: {1} {2}" -f $code, $_.Exception.Message, $bd)
    if ($OutFile) {
        [System.IO.File]::WriteAllText($OutFile, $text, (New-Object System.Text.UTF8Encoding $false))
        exit 1
    }
    Write-Output $text
    exit 1
}
if ($OutFile) {
    [System.IO.File]::WriteAllText($OutFile, $text, (New-Object System.Text.UTF8Encoding $false))
} else {
    Write-Output $text
}
