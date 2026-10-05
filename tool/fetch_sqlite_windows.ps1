# Downloads the official x64 sqlite3.dll so `flutter test` can run Drift tests on Windows.
$ErrorActionPreference = 'Stop'
$url = 'https://www.sqlite.org/2025/sqlite-dll-win-x64-3500400.zip'
$dest = Join-Path $PSScriptRoot 'windows'
$zip = Join-Path $env:TEMP 'sqlite-dll-win-x64.zip'

New-Item -ItemType Directory -Force $dest | Out-Null
Invoke-WebRequest -Uri $url -OutFile $zip
Expand-Archive -Path $zip -DestinationPath $dest -Force
Remove-Item (Join-Path $dest 'sqlite3.def') -ErrorAction SilentlyContinue
Remove-Item $zip
Write-Host "sqlite3.dll installed to $dest"
