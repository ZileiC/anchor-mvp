param([switch]$Rebuild)
# Builds (if needed) and launches the Windows desktop app.
#
# The app auto-starts a bundled backend from `dist\windows\backend\anchor_backend.exe`.
# 2026-11-12: this used to launch the app even when that file was missing, which
# opened a window that only said 本地服务未启动 — exactly what a fresh clone (and a
# teammate's download) ran into. Now the backend is built when it is missing, and
# the script refuses to launch a build that cannot work.
. "$PSScriptRoot\_common.ps1"
$ErrorActionPreference = 'Stop'

$exe = Join-Path $script:MobileDir 'dist\windows\anchor_app.exe'
if ($Rebuild -or -not (Test-Path $exe)) {
    & (Join-Path $PSScriptRoot 'build_windows.ps1') -Configuration Debug
}

$backendSrc = Join-Path $script:BackendDir 'dist\anchor_backend.exe'
$backendDir = Join-Path $script:MobileDir 'dist\windows\backend'
$backendDst = Join-Path $backendDir 'anchor_backend.exe'

if ($Rebuild -or -not (Test-Path $backendSrc)) {
    Write-Host '[app] building the bundled backend ...' -ForegroundColor Cyan
    & (Join-Path $PSScriptRoot 'build_backend.ps1')
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $backendSrc)) {
        throw 'backend build failed. The app needs backend\anchor_backend.exe next to it; without it the window only says 本地服务未启动.'
    }
}

& $script:VenvPython (Join-Path $PSScriptRoot 'windows_artifacts.py') $backendSrc
if ($LASTEXITCODE -ne 0) { throw 'Cached backend failed the artifact check. Run scripts/build_backend.ps1 first.' }

New-Item -ItemType Directory -Force -Path $backendDir | Out-Null
if (-not (Test-Path $backendDst) -or
    ((Get-FileHash -LiteralPath $backendSrc).Hash -ne (Get-FileHash -LiteralPath $backendDst).Hash)) {
    Copy-Item $backendSrc $backendDst -Force
    Write-Host '[app] bundled backend copied next to the exe' -ForegroundColor Cyan
}

Start-Process -FilePath $exe
Write-Host "[app] launched $exe" -ForegroundColor Green
