param([switch]$Rebuild)
# Builds (if needed) and launches the Windows desktop app.
# The app auto-starts a bundled backend; make sure one exists next to the exe.
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_common.ps1"

$exe = Join-Path $script:MobileDir 'dist\windows\anchor_app.exe'
if ($Rebuild -or -not (Test-Path $exe)) {
    & (Join-Path $PSScriptRoot 'build_windows.ps1') -Configuration Debug
}

$backendSrc = Join-Path $script:BackendDir 'dist\anchor_backend.exe'
$backendDir = Join-Path $script:MobileDir 'dist\windows\backend'
$backendDst = Join-Path $backendDir 'anchor_backend.exe'
if (Test-Path $backendSrc) {
    New-Item -ItemType Directory -Force -Path $backendDir | Out-Null
    if (-not (Test-Path $backendDst) -or ((Get-Item $backendSrc).LastWriteTime -gt (Get-Item $backendDst).LastWriteTime)) {
        Copy-Item $backendSrc $backendDst -Force
        Write-Host '[app] bundled backend copied next to the exe' -ForegroundColor Cyan
    }
} else {
    Write-Host '[app] no bundled backend found; start scripts\run_backend.ps1 first or run scripts\build_backend.ps1' -ForegroundColor DarkYellow
}

Start-Process -FilePath $exe
Write-Host "[app] launched $exe" -ForegroundColor Green
