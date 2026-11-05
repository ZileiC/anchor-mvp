param(
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Debug',
    [switch]$NoSync
)
# Builds the Flutter Windows runner.
#
# Why this script exists:
#  * CMake 4.1 crashes ("stack buffer overrun") when the project path contains non-ASCII
#    characters, and cppwinrt fails the same way. The workspace path has "鈪?26 Fall",
#    so the build happens in an ASCII-only mirror under %LOCALAPPDATA%.
#  * flutter_tts's Windows CMake asks for nuget.exe on PATH.
#  * CMake 4.x no longer reports CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT, which makes the
#    install step try "C:\Program Files\<app>"; we force the bundle dir.
$ErrorActionPreference = 'Continue'  # native tools write to stderr; exit codes are checked explicitly
. "$PSScriptRoot\_common.ps1"

$dst = Join-Path $script:BuildRoot 'mobile'
$flutter = Get-Flutter
Ensure-Nuget | Out-Null

if (-not $NoSync) {
    Sync-MobileToAscii | Out-Null
}

# Guarantee the install-prefix fix in the mirrored copy.
$cmakeFile = Join-Path $dst 'windows\CMakeLists.txt'
if (Test-Path $cmakeFile) {
    $content = Get-Content $cmakeFile -Raw
    if ($content -match 'CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT') {
        $content = $content -replace 'if\(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT\)', 'if(TRUE) # Anchor: CMake 4.x install-prefix fix'
        Set-Content -Path $cmakeFile -Value $content -Encoding utf8
    }
}

Push-Location $dst
try {
    & $flutter pub get 2>&1 | Out-String | Write-Host
    if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed' }

    & $flutter build windows --$($Configuration.ToLower()) 2>&1 | Out-String | Write-Host
    if ($LASTEXITCODE -ne 0) { throw 'flutter build windows failed' }

    $runner = Join-Path $dst "build\windows\x64\runner\$Configuration"
    $exe = Join-Path $runner 'anchor_app.exe'
    if (-not (Test-Path $exe)) { throw "built exe not found: $exe" }

    $out = Join-Path $script:MobileDir 'dist\windows'
    if (Test-Path $out) { Remove-Item -Recurse -Force $out }
    New-Item -ItemType Directory -Force -Path $out | Out-Null
    Copy-Item -Recurse -Force (Join-Path $runner '*') $out
    $built = Join-Path $out 'anchor_app.exe'
    Write-Host "[build] OK -> $built" -ForegroundColor Green
    Write-Host "[build] run:  $built" -ForegroundColor Green
} finally {
    Pop-Location
}

