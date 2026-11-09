# Builds the self-contained backend for the Windows demo package:
#   anchor/backend/dist/anchor_backend.exe   (single file, windowed, no Python needed)
#
# Usage (from anywhere):
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\build_backend.ps1
#
# The exe serves 127.0.0.1:8077 from app/entrypoint.py, seeds demo data into
# <exe dir>\data\anchor.db on first start (or %LOCALAPPDATA%\Anchor when the exe
# dir is read-only) and exits 0 when the port is already taken.
param([switch]$SkipDeps)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_common.ps1"

$PipIndex = if ($env:ANCHOR_PIP_INDEX) { $env:ANCHOR_PIP_INDEX } else { 'https://pypi.tuna.tsinghua.edu.cn/simple' }

if (-not $SkipDeps) {
    Ensure-PythonVenv
    Write-Host '[build] installing build dependencies (PyInstaller) ...' -ForegroundColor Cyan
    & $script:VenvPython -m pip install --quiet --disable-pip-version-check --index-url $PipIndex -r (Join-Path $script:BackendDir 'requirements-build.txt')
    if ($LASTEXITCODE -ne 0) { throw 'pip install -r requirements-build.txt failed' }
}

$distDir = Join-Path $script:BackendDir 'dist'
$workDir = Join-Path $script:BackendDir 'build'
$exe = Join-Path $distDir 'anchor_backend.exe'
New-Item -ItemType Directory -Force -Path $distDir, $workDir | Out-Null
if (Test-Path $exe) { Remove-Item $exe -Force }

Write-Host '[build] running PyInstaller (one-file, windowed) ...' -ForegroundColor Cyan
Push-Location $script:BackendDir
try {
    & $script:VenvPython -m PyInstaller `
        --noconfirm --clean `
        --name anchor_backend `
        --onefile --noconsole `
        --add-data "migrations;migrations" `
        --add-data "../content/activities.json;content" `
        --collect-submodules uvicorn `
        --paths . `
        --distpath $distDir --workpath $workDir `
        app/entrypoint.py
    if ($LASTEXITCODE -ne 0) { throw "PyInstaller failed (exit $LASTEXITCODE)" }
    Write-Host "[build] PyInstaller exit code: $LASTEXITCODE" -ForegroundColor DarkGray
} finally {
    Pop-Location
}

if (-not (Test-Path $exe)) { throw "missing build output: $exe" }
$info = Get-Item $exe
$sizeMb = [math]::Round($info.Length / 1MB, 1)
Write-Host ''
Write-Host "[build] backend exe -> $($info.FullName)" -ForegroundColor Green
Write-Host ("[build] size {0} MB ({1} bytes)" -f $sizeMb, $info.Length) -ForegroundColor Green
Write-Host '[build] smoke it from a clean directory: scripts\test_backend_exe.ps1' -ForegroundColor Green
