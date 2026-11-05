param([switch]$Rebuild)
# Builds (if needed) and launches the Windows desktop app.
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_common.ps1"

$exe = Join-Path $script:MobileDir 'dist\windows\anchor_app.exe'
if ($Rebuild -or -not (Test-Path $exe)) {
    & (Join-Path $PSScriptRoot 'build_windows.ps1') -Configuration Debug
}
Start-Process -FilePath $exe
Write-Host "[app] launched $exe" -ForegroundColor Green
