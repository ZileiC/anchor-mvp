param(
    [switch]$BackendOnly,
    [switch]$SkipBuild,
    [switch]$SkipFlutter
)
$ErrorActionPreference = 'Continue'  # native tools write to stderr; exit codes are checked explicitly
. "$PSScriptRoot\_common.ps1"

$failed = 0
function Run-Step {
    param([string]$Name, [scriptblock]$Body)
    Write-Host ''
    Write-Host "=== $Name ===" -ForegroundColor Yellow
    try {
        & $Body
        if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) { throw "exit code $LASTEXITCODE" }
        Write-Host "=== OK: $Name ===" -ForegroundColor Green
    } catch {
        $script:failed++
        Write-Host "=== FAILED: $Name -> $_" -ForegroundColor Red
    }
}

Ensure-PythonVenv

Run-Step 'backend: pytest' {
    Push-Location $script:BackendDir
    try { & $script:VenvPython -m pytest -q } finally { Pop-Location }
}

if (-not $BackendOnly) {
    $flutter = Get-Flutter
    $dart = Join-Path (Split-Path $flutter) 'dart.bat'
    if (-not $SkipFlutter) {
        Run-Step 'dart format check' {
            Push-Location $script:MobileDir
            try {
                $targets = @()
                foreach ($t in @('lib', 'test')) { if (Test-Path (Join-Path $script:MobileDir $t)) { $targets += $t } }
                if ($targets.Count -gt 0) {
                    & $dart format --output=none --set-exit-if-changed @targets 2>&1 | Out-String | Write-Host
                } else {
                    Write-Host '(no lib/test yet - skipped)'
                }
            } finally { Pop-Location }
        }
    }

    # flutter analyze / flutter test / build all run from the ASCII mirror: the Dart
    # analysis server cannot parse non-ASCII project paths (see _common.ps1).
    $asciiMobile = $null
    if (-not $SkipFlutter -or -not $SkipBuild) {
        Run-Step 'flutter pub get (ascii mirror)' {
            $script:AsciiMobile = Sync-MobileToAscii
            Ensure-Nuget | Out-Null
            Push-Location $script:AsciiMobile
            try { & $flutter pub get 2>&1 | Out-String | Write-Host } finally { Pop-Location }
        }
        $asciiMobile = $script:AsciiMobile
    }

    if (-not $SkipFlutter) {
        Run-Step 'flutter analyze' {
            Push-Location $asciiMobile
            try { & $flutter analyze 2>&1 | Out-String | Write-Host } finally { Pop-Location }
        }
        Run-Step 'flutter test' {
            Push-Location $asciiMobile
            try { & $flutter test 2>&1 | Out-String | Write-Host } finally { Pop-Location }
        }
    }
    if (-not $SkipBuild) {
        Run-Step 'flutter build windows (ascii build dir)' {
            & (Join-Path $PSScriptRoot 'build_windows.ps1') -Configuration Debug -NoSync
        }
    }
}

# Demo seed + worker smoke (only once those files exist).
$seed = Join-Path $PSScriptRoot 'seed_demo.py'
if ((Test-Path $seed) -and -not $BackendOnly) {
    Run-Step 'seed demo (check)' {
        Push-Location (Join-Path $script:RepoRoot 'backend')
        try { & $script:VenvPython $seed --check } finally { Pop-Location }
    }
}

Write-Host ''
if ($failed -gt 0) {
    Write-Host "VERIFY FAILED ($failed step(s))" -ForegroundColor Red
    exit 1
}
Write-Host 'VERIFY GREEN' -ForegroundColor Green
exit 0

