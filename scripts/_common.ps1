# PowerShell helper functions shared by the Anchor scripts.
# Dot-source from repo scripts:  . "$PSScriptRoot\_common.ps1"
$ErrorActionPreference = 'Continue'  # dev scripts call native tools that write to stderr

$script:RepoRoot = Split-Path $PSScriptRoot -Parent
$script:BackendDir = Join-Path $RepoRoot 'backend'
$script:MobileDir = Join-Path $RepoRoot 'mobile'
$script:VenvPython = Join-Path $RepoRoot '.venv\Scripts\python.exe'
$script:PipIndex = if ($env:ANCHOR_PIP_INDEX) { $env:ANCHOR_PIP_INDEX } else { 'https://pypi.tuna.tsinghua.edu.cn/simple' }
$script:ToolsDir = Join-Path $env:LOCALAPPDATA 'anchor-tools'
$script:BuildRoot = Join-Path $env:LOCALAPPDATA 'anchor-build'

function Get-Flutter {
    $cmd = Get-Command flutter -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return 'C:\flutter\bin\flutter.bat'
}

function Ensure-PythonVenv {
    if (-not (Test-Path $script:VenvPython)) {
        Write-Host '[setup] creating venv ...' -ForegroundColor Cyan
        python -m venv (Join-Path $script:RepoRoot '.venv')
        if ($LASTEXITCODE -ne 0) { throw 'python -m venv failed' }
    }
    & $script:VenvPython -m pip install --quiet --disable-pip-version-check --index-url $script:PipIndex -r (Join-Path $script:BackendDir 'requirements.txt')
    if ($LASTEXITCODE -ne 0) { throw 'pip install failed' }
}

function Ensure-Nuget {
    New-Item -ItemType Directory -Force -Path $script:ToolsDir | Out-Null
    $nuget = Join-Path $script:ToolsDir 'nuget.exe'
    if (-not (Test-Path $nuget)) {
        Write-Host '[setup] downloading nuget.exe (flutter_tts windows build dependency) ...' -ForegroundColor Cyan
        Invoke-WebRequest -Uri 'https://dist.nuget.org/win-x86-commandline/latest/nuget.exe' -OutFile $nuget -UseBasicParsing
    }
    if (-not (($env:PATH -split ';') -contains $script:ToolsDir)) {
        $env:PATH = "$script:ToolsDir;$env:PATH"
    }
    return $nuget
}

function Sync-MobileToAscii {
    # Dart's analysis server crashes (JSON-RPC "Unexpected end of input") when the
    # project path contains non-ASCII characters, and CMake 4.x crashes on the same
    # path. Every Flutter step therefore runs against an ASCII-only mirror.
    $src = $script:MobileDir
    $dst = Join-Path $script:BuildRoot 'mobile'
    New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
    Write-Host "[flutter] syncing source -> $dst" -ForegroundColor Cyan
    robocopy $src $dst /E /PURGE /XD build .dart_tool ephemeral dist .git /NFL /NDL /NJH /NJS /NP /R:2 /W:2 | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy failed ($LASTEXITCODE)" }
    return $dst
}

function Invoke-Step {
    param([string]$Name, [string]$Command, [string[]]$Arguments = @(), [string]$WorkDir = $script:RepoRoot)
    Write-Host ''
    Write-Host "=== $Name ===" -ForegroundColor Yellow
    & $Command @Arguments
        if ($LASTEXITCODE -ne 0) { throw "FAILED: $Name (exit $LASTEXITCODE)" }
    Write-Host "=== OK: $Name ===" -ForegroundColor Green
}

