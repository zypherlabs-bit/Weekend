$src = "d:\Projects\Weekend\supabase\migrations"
Get-ChildItem (Join-Path $src "*.sql") | ForEach-Object {
  $b64 = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes((Get-Content $_.FullName -Raw)))
  $args = "sh -c 'mkdir -p /tmp/migrations; echo " + $b64 + " | base64 -d > /tmp/migrations/" + $_.Name + "'"
  $out = docker exec -i wknd4 $args 2>&1
  Write-Output "$(Fix-FilePath $_.FullName) -> $(if($out){ $out } else { 'ok' })"
}