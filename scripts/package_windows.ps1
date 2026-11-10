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

这台电脑上没有设置界面
  电脑是给老人用的「终端」：说话、玩一玩、打电话、停止，就这些。
  所有配置（AI 模型、语音识别 key、家人联系方式、周报）都在**家人的手机 App** 上做，
  手机和电脑连同一个 Wi-Fi 即可。手机端不提供语音功能。

接入真模型（否则回复是离线模板）
  在手机 App 的「AI 接入」里填 DeepSeek API Key（预设已是 base URL + deepseek-flash）
  和语音识别 key（预设已是 SiliconFlow base URL + Qwen3-ASR），保存后测试。
  Key 只保存在这台电脑的 backend\data\anchor.db，接口返回时打码。

声音
  * 默认走后端在线神经语音（微软 Edge 神经音色，中文自然），需要联网。
  * 断网或合成失败时自动退回 Windows 系统语音（SAPI），能出声但很机器人。
  * 说完到出声之间会有几秒合成等待。

演示提示
  * 主动问候只在 App 前台、且在问候窗口内出现；演示数据默认窗口 09:00–21:00。
  * 所有姓名/记录都是合成演示数据，不是真实老人数据。
  * 后端数据目录：backend\data\（删掉即可重置演示）。
  * 诊断日志：backend\data\backend.log（若存在）。

已知限制
  * 这是 Flutter Debug 构建，启动略慢、体积偏大。
  * 后端监听 0.0.0.0:8077（手机端才能连上）；若端口被占用，App 会当作已有后端。
  * 详细限制见仓库 docs/limitations.md。
'@
Set-Content -Path (Join-Path $stage 'README-DEMO.txt') -Value $readme -Encoding utf8

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
Remove-Item -Recurse -Force $stageRoot -ErrorAction SilentlyContinue
