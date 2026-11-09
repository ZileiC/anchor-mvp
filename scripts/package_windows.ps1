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

Write-Host '[package] staging app files ...' -ForegroundColor Cyan
Get-ChildItem $appDir -Recurse -File | Where-Object { $_.Extension -ne '.pdb' } | ForEach-Object {
    $rel = $_.FullName.Substring($appDir.Length + 1)
    $dest = Join-Path $stage $rel
    New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
    Copy-Item $_.FullName $dest -Force
}

New-Item -ItemType Directory -Force -Path (Join-Path $stage 'backend') | Out-Null
Copy-Item $backendExe (Join-Path $stage 'backend\anchor_backend.exe') -Force

$readme = @'
Anchor MVP — Windows 自包含演示版
=================================

双击 anchor_app.exe 即可。App 会在后台自动启动内置后端（backend\anchor_backend.exe），
等它就绪后进入登录页；退出 App 时会自动关闭它。不需要安装 Python / Flutter，也不需要手动开后端。

首次启动会在 backend\data\anchor.db 生成演示数据（林秀兰 + 家人 Mei）。
如果程序目录不可写，数据库会放到 %LOCALAPPDATA%\Anchor\anchor.db。

演示账号
  1 = 林秀兰（老人）
  2 = Mei（家人）

接入真模型（否则回复是离线模板）
  Settings → AI 接入（模型/语音）→ 填 DeepSeek API Key（预设已填好 base URL + deepseek-chat）
  → 保存 → 测试连接。Key 只保存在本机 backend\data\anchor.db，接口返回时打码。
  语音识别：Windows 版默认用本机 System.Speech（不要 key）；没有中文识别包时请在同一页面
  配置 OpenAI 兼容的 ASR，或直接打字。

演示提示
  * 主动问候只在 App 前台、且在问候窗口内出现；演示数据默认窗口 09:00–21:00，
    可在 Settings → 问候时间 里调整。
  * 声音使用 Windows 系统语音（SAPI），不是目标音色。
  * 所有姓名/记录都是合成演示数据，不是真实老人数据。
  * 后端数据目录：backend\data\（删掉即可重置演示）。
  * 诊断日志：backend\data\backend.log（若存在）。

已知限制
  * 这是 Flutter Debug 构建，启动略慢、体积偏大。
  * 端口固定 127.0.0.1:8077；若被占用，App 会直接当作“已有后端”。
  * 详细限制见仓库 docs/limitations.md。
'@
Set-Content -Path (Join-Path $stage 'README-DEMO.txt') -Value $readme -Encoding utf8

$zip = Join-Path $script:MobileDir "dist\AnchorDemo-$Version.zip"
if (Test-Path $zip) { Remove-Item -Force $zip }
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::Open($zip, 'Create')
$count = 0
Get-ChildItem $stage -Recurse -File | ForEach-Object {
    $rel = $_.FullName.Substring($stage.Length + 1)
    [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
        $archive, $_.FullName, $rel, [System.IO.Compression.CompressionLevel]::Optimal
    ) | Out-Null
    $count++
}
$archive.Dispose()

$size = [math]::Round((Get-Item $zip).Length / 1MB, 1)
Write-Host "[package] $count files -> $zip ($size MB)" -ForegroundColor Green
Write-Host '[package] README-DEMO.txt included; app auto-starts backend.' -ForegroundColor Green
Remove-Item -Recurse -Force $stageRoot -ErrorAction SilentlyContinue
