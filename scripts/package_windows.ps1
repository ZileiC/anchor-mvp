param(
    [switch]$SkipBuild,
    [string]$Version = "0.2.0"
)
# Assembles the self-contained Windows demo package:
#   anchor_app.exe (+ Flutter data)  +  backend\anchor_backend.exe  +  README-DEMO.txt
# and zips it to mobile\dist\AnchorDemo-$Version.zip.
$ErrorActionPreference = 'Continue'
. "$PSScriptRoot\_common.ps1"

$appDir = Join-Path $script:MobileDir 'dist\windows'
$backendExe = Join-Path $script:BackendDir 'dist\anchor_backend.exe'

if (-not $SkipBuild) {
    Write-Host '[package] building Flutter Windows app ...' -ForegroundColor Cyan
    & (Join-Path $PSScriptRoot 'build_windows.ps1') -Configuration Debug
    if ($LASTEXITCODE -ne 0) { throw 'flutter build failed' }

    Write-Host '[package] building backend exe ...' -ForegroundColor Cyan
    & (Join-Path $PSScriptRoot 'build_backend.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'backend build failed' }
}

if (-not (Test-Path (Join-Path $appDir 'anchor_app.exe'))) {
    throw "missing app build: $appDir\anchor_app.exe (run scripts\build_windows.ps1)"
}
if (-not (Test-Path $backendExe)) {
    throw "missing backend build: $backendExe (run scripts\build_backend.ps1)"
}

$stageRoot = Join-Path $env:TEMP "anchor-package-$Version"
if (Test-Path $stageRoot) { Remove-Item -Recurse -Force $stageRoot }
$stage = Join-Path $stageRoot 'AnchorDemo'
New-Item -ItemType Directory -Force -Path $stage | Out-Null

# Resolve 8.3 short TEMP paths (e.g. JHARAY~1) to their long form: Get-ChildItem
# returns long paths, so substring math on the short $stage string is wrong and
# produced zip entries like "\anchor_app.exe" / "o/anchor_app.exe".
$stageFull = (Get-Item $stage).FullName
$appDirFull = (Get-Item $appDir).FullName

Write-Host '[package] staging app files ...' -ForegroundColor Cyan
Get-ChildItem $appDir -Recurse -File | Where-Object { $_.Extension -ne '.pdb' } | ForEach-Object {
    # Entry names must be RELATIVE and use forward slashes; a leading backslash
    # makes Windows Explorer and several unzip tools hide/garble the archive.
    $rel = $_.FullName.Substring($appDirFull.Length).TrimStart('\', '/').Replace('\', '/')
    $dest = Join-Path $stage $rel
    New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
    Copy-Item $_.FullName $dest -Force
}

New-Item -ItemType Directory -Force -Path (Join-Path $stage 'backend') | Out-Null
Copy-Item $backendExe (Join-Path $stage 'backend\anchor_backend.exe') -Force

# The demo readme ships inside the ZIP. It is copied from a tracked UTF-8 file
# rather than embedded here: a here-string with Chinese in this script was
# written out as mojibake, because PowerShell reads the script with the system
# ANSI code page while Set-Content wrote UTF-8 (found 2026-11-16).
Copy-Item (Join-Path (Split-Path $PSScriptRoot) 'docs\README-DEMO.txt') (Join-Path $stage 'README-DEMO.txt') -Force

$zip = Join-Path $script:MobileDir "dist\AnchorDemo-$Version.zip"
if (Test-Path $zip) { Remove-Item -Force $zip }
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::Open($zip, 'Create')
$count = 0
Get-ChildItem $stage -Recurse -File | ForEach-Object {
    $rel = $_.FullName.Substring($stageFull.Length).TrimStart('\', '/').Replace('\', '/')
    [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
        $archive, $_.FullName, $rel, [System.IO.Compression.CompressionLevel]::Optimal
    ) | Out-Null
    $count++
}
$archive.Dispose()

$size = [math]::Round((Get-Item $zip).Length / 1MB, 1)
Write-Host "[package] $count files -> $zip ($size MB)" -ForegroundColor Green
Write-Host '[package] README-DEMO.txt included; app auto-starts backend.' -ForegroundColor Green

# 2026-11-12: also refresh the copy that ships INSIDE the repository. A plain
# "Code -> Download ZIP" has to contain something double-clickable, so
# `release\windows` is tracked; it must never drift behind a new build.
$shipped = Join-Path (Split-Path $PSScriptRoot) 'release\windows'
New-Item -ItemType Directory -Force -Path $shipped | Out-Null
robocopy $stage $shipped /E /XF *.pdb /NFL /NDL /NJH /NJS /NP | Out-Null
foreach ($entry in @('anchor_app.exe', 'backend\anchor_backend.exe', 'README-DEMO.txt')) {
    if (-not (Test-Path (Join-Path $shipped $entry))) {
        throw "release\windows is incomplete after packaging: missing $entry"
    }
}
Write-Host '[package] release\windows refreshed (the runnable folder committed to the repo)' -ForegroundColor Green

Remove-Item -Recurse -Force $stageRoot -ErrorAction SilentlyContinue
