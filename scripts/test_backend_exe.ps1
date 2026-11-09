# Smoke-tests the packaged backend exactly like the Windows demo does:
# copy anchor_backend.exe to a clean %TEMP% dir, clear every ANCHOR_* variable,
# start it on a free port, poll /api/v1/health, check the seeded demo users (1, 2),
# consents and /api/v1/digests, then stop it and delete the temp dir.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\test_backend_exe.ps1
#   ... -ExePath ..\anchor_backend.exe -KeepTemp      # debug a copy
param(
    [string]$ExePath = '',
    [int]$StartupTimeoutSeconds = 90,
    [switch]$KeepTemp
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_common.ps1"

if (-not $ExePath) { $ExePath = Join-Path $script:BackendDir 'dist\anchor_backend.exe' }
if (-not (Test-Path $ExePath)) { throw "missing exe: $ExePath (run scripts\build_backend.ps1 first)" }
$ExePath = (Resolve-Path $ExePath).Path

function Get-FreePort {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $listener.Start()
    try { return ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port }
    finally { $listener.Stop() }
}

function Invoke-Api {
    param([string]$Method, [string]$Url, [string]$Token = '', $Body = $null)
    # .NET WebRequest + an explicit UTF-8 StreamReader: Windows PowerShell 5.1's
    # Invoke-RestMethod decodes a charset-less application/json body as Latin-1,
    # which would mojibake the seeded Chinese display name.
    $request = [System.Net.WebRequest]::Create($Url)
    $request.Method = $Method
    $request.Timeout = 10000
    if ($Token) { $request.Headers.Add('Authorization', "Bearer $Token") }
    if ($null -ne $Body) {
        $payload = $Body | ConvertTo-Json -Depth 5 -Compress
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
        $request.ContentType = 'application/json; charset=utf-8'
        $request.ContentLength = $bytes.Length
        $requestStream = $request.GetRequestStream()
        try { $requestStream.Write($bytes, 0, $bytes.Length) } finally { $requestStream.Close() }
    }
    try {
        $response = $request.GetResponse()
    } catch [System.Net.WebException] {
        $detail = ''
        if ($_.Exception.Response) {
            $errorReader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream(), [System.Text.Encoding]::UTF8)
            try { $detail = $errorReader.ReadToEnd() } finally { $errorReader.Close() }
        }
        throw "HTTP $Method $Url failed: $($_.Exception.Message) $detail"
    }
    $reader = New-Object System.IO.StreamReader($response.GetResponseStream(), [System.Text.Encoding]::UTF8)
    try { $text = $reader.ReadToEnd() } finally { $reader.Close(); $response.Close() }
    if (-not $text) { return $null }
    return $text | ConvertFrom-Json
}

function Invoke-ApiBytes {
    # Binary sibling of Invoke-Api: /api/v1/tts answers raw audio, so the smoke
    # must read the response stream as bytes instead of decoding JSON.
    param([string]$Url, [string]$Token = '', $Body = $null)
    $request = [System.Net.WebRequest]::Create($Url)
    $request.Method = 'POST'
    $request.Timeout = 30000
    if ($Token) { $request.Headers.Add('Authorization', "Bearer $Token") }
    $payload = $Body | ConvertTo-Json -Depth 5 -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
    $request.ContentType = 'application/json; charset=utf-8'
    $request.ContentLength = $bytes.Length
    $requestStream = $request.GetRequestStream()
    try { $requestStream.Write($bytes, 0, $bytes.Length) } finally { $requestStream.Close() }
    try {
        $response = $request.GetResponse()
    } catch [System.Net.WebException] {
        $detail = ''
        if ($_.Exception.Response) {
            $errorReader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream(), [System.Text.Encoding]::UTF8)
            try { $detail = $errorReader.ReadToEnd() } finally { $errorReader.Close() }
        }
        throw "HTTP POST $Url failed: $($_.Exception.Message) $detail"
    }
    $contentType = $response.ContentType
    $memory = New-Object System.IO.MemoryStream
    try { $response.GetResponseStream().CopyTo($memory) } finally { $response.Close() }
    return [pscustomobject]@{ ContentType = $contentType; Bytes = $memory.ToArray(); Length = $memory.Length }
}

function Stop-SmokeProcess {
    param($Process, [string]$ExecutablePath)
    if ($Process) {
        try { if (-not $Process.HasExited) { Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue } } catch { }
    }
    # A PyInstaller --onefile exe runs the app in a child process; kill anything
    # still executing from this exact (random) temp copy.
    Get-Process -Name 'anchor_backend' -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            if ($_.Path -eq $ExecutablePath) { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }
        } catch { }
    }
    Start-Sleep -Milliseconds 400
}

$tempRoot = Join-Path $env:TEMP ('anchor-backend-smoke-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$exe = Join-Path $tempRoot 'anchor_backend.exe'
$port = Get-FreePort
$base = "http://127.0.0.1:$port/api/v1"
$proc = $null
$savedEnv = @{}
$failure = $null

try {
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
    Copy-Item $ExePath $exe -Force

    # "No env": the demo machine has no configuration at all; only the free port
    # is passed so the smoke can never collide with a real backend.
    Get-ChildItem Env: | Where-Object { $_.Name -like 'ANCHOR_*' } | ForEach-Object {
        $savedEnv[$_.Name] = $_.Value
        Remove-Item -Path "Env:$($_.Name)" -ErrorAction SilentlyContinue
    }
    $env:ANCHOR_PORT = "$port"

    $started = Get-Date
    $proc = Start-Process -FilePath $exe -WorkingDirectory $tempRoot -PassThru -WindowStyle Hidden

    $health = $null
    while (((Get-Date) - $started).TotalSeconds -lt $StartupTimeoutSeconds) {
        try {
            $health = Invoke-Api -Method GET -Url "$base/health"
            break
        } catch {
            if ($proc.HasExited) {
                $log = Join-Path $tempRoot 'data\backend.log'
                $tail = if (Test-Path $log) { Get-Content $log -Raw } else { '(no log)' }
                throw "backend exited before becoming healthy (exit $($proc.ExitCode))`n$tail"
            }
            Start-Sleep -Milliseconds 500
        }
    }
    if ($null -eq $health) { throw "backend did not become healthy within $StartupTimeoutSeconds s" }
    $startupSeconds = [math]::Round(((Get-Date) - $started).TotalSeconds, 2)

    # -- assertions --------------------------------------------------------
    if ($health.status -ne 'ok') { throw "health status was '$($health.status)'" }
    if ($health.version -ne '0.1.0') { throw "unexpected health version '$($health.version)'" }

    $seniorLogin = Invoke-Api -Method POST -Url "$base/dev/login" -Body @{ user_id = 1 }
    $caregiverLogin = Invoke-Api -Method POST -Url "$base/dev/login" -Body @{ user_id = 2 }
    if (-not $seniorLogin.access_token) { throw 'senior #1 login returned no token' }
    if (-not $caregiverLogin.access_token) { throw 'caregiver #2 login returned no token' }

    $senior = Invoke-Api -Method GET -Url "$base/me" -Token $seniorLogin.access_token
    $caregiver = Invoke-Api -Method GET -Url "$base/me" -Token $caregiverLogin.access_token
    if ($senior.id -ne 1 -or $senior.role -ne 'senior') { throw "senior #1 is wrong: $($senior | ConvertTo-Json -Compress)" }
    if ($caregiver.id -ne 2 -or $caregiver.role -ne 'caregiver') { throw "caregiver #2 is wrong: $($caregiver | ConvertTo-Json -Compress)" }
    if ($caregiver.relationship_status -ne 'accepted' -or $caregiver.senior_id -ne 1) {
        throw "caregiver relationship is not accepted: $($caregiver | ConvertTo-Json -Compress)"
    }
    # Compare as Unicode code points: this .ps1 has no BOM and Windows PowerShell
    # reads non-ASCII literals as ANSI, so the seeded senior name is asserted
    # without embedding any non-ASCII character in this file.
    $seniorNameCodes = (([int[]][char[]]$senior.display_name) | ForEach-Object { 'U+{0:X4}' -f $_ }) -join ' '
    if ($seniorNameCodes -ne 'U+6797 U+79C0 U+5170') {
        throw "senior #1 display_name mismatch: expected U+6797 U+79C0 U+5170, got '$seniorNameCodes'"
    }

    $consents = Invoke-Api -Method GET -Url "$base/consents" -Token $seniorLogin.access_token
    $denied = @($consents.items | Where-Object { -not $_.allowed })
    $topics = @($consents.items | Where-Object { $_.capability -eq 'share_topic' -and $_.allowed } | ForEach-Object { $_.topic })
    if (@($consents.items).Count -ne 9) { throw "expected 9 consent rows, got $(@($consents.items).Count)" }
    if ($denied.Count -ne 0) { throw "demo consents should all be allowed, denied: $($denied | ConvertTo-Json -Compress)" }
    if ($topics.Count -ne 5) { throw "expected 5 shared topics, got $($topics -join ',')" }

    # The exe seeds the foreground demo window 09:00-21:00 (documented in app/demo_seed.py).
    $preferences = Invoke-Api -Method GET -Url "$base/preferences" -Token $seniorLogin.access_token
    if ($preferences.greeting_start -ne '09:00' -or $preferences.greeting_end -ne '21:00') {
        throw "auto-seed did not use the demo greeting window: $($preferences | ConvertTo-Json -Compress)"
    }

    $digests = Invoke-Api -Method GET -Url "$base/digests" -Token $seniorLogin.access_token
    if ($null -eq $digests.items) { throw '/api/v1/digests did not return an items array' }
    $caregiverDigests = Invoke-Api -Method GET -Url "$base/digests" -Token $caregiverLogin.access_token
    if ($null -eq $caregiverDigests.items) { throw 'caregiver /api/v1/digests did not return an items array' }

    # Real neural speech from the packaged exe: the app asks this endpoint for every
    # sentence it says, so a frozen-exe TTS failure must surface here, not on stage.
    # Only `text` is sent on purpose: the app itself sends no voice/rate, so this is
    # exactly the demo path (server default voice, slowed for older ears).
    $ttsStarted = Get-Date
    $tts = Invoke-ApiBytes -Url "$base/tts" -Token $seniorLogin.access_token -Body @{
        text = 'Anchor smoke test. One, two, three.'
    }
    $ttsSeconds = [math]::Round(((Get-Date) - $ttsStarted).TotalSeconds, 2)
    if ($tts.ContentType -notlike 'audio/mpeg*') { throw "tts content type was '$($tts.ContentType)'" }
    if ($tts.Length -lt 3000) { throw "tts audio is only $($tts.Length) bytes" }
    $isMp3 = ($tts.Bytes[0] -eq 0x49 -and $tts.Bytes[1] -eq 0x44 -and $tts.Bytes[2] -eq 0x33) -or
             ($tts.Bytes[0] -eq 0xFF -and ($tts.Bytes[1] -band 0xE0) -eq 0xE0)
    if (-not $isMp3) {
        $magic = '{0:X2} {1:X2} {2:X2}' -f $tts.Bytes[0], $tts.Bytes[1], $tts.Bytes[2]
        throw "tts payload is not MPEG audio (first bytes: $magic)"
    }

    $dbFile = Join-Path $tempRoot 'data\anchor.db'
    if (-not (Test-Path $dbFile)) { throw "database was not created next to the exe: $dbFile" }
    $logFile = Join-Path $tempRoot 'data\backend.log'
    if (-not (Test-Path $logFile)) { throw "windowed exe did not create its log: $logFile" }

    # A second copy (e.g. double-clicked twice) must disappear quietly: the desktop
    # app already has a backend on this port.
    $second = Start-Process -FilePath $exe -WorkingDirectory $tempRoot -PassThru -WindowStyle Hidden
    if (-not $second.WaitForExit(30000)) {
        Stop-Process -Id $second.Id -Force -ErrorAction SilentlyContinue
        throw 'a second backend instance kept running on a busy port'
    }
    if ($second.ExitCode -ne 0) {
        throw "second instance exited $($second.ExitCode); a busy port must exit 0"
    }
    $healthAfter = Invoke-Api -Method GET -Url "$base/health"
    if ($healthAfter.status -ne 'ok') { throw 'the first backend stopped serving after the port clash' }

    # -- report ------------------------------------------------------------
    $exeSizeMb = [math]::Round((Get-Item $ExePath).Length / 1MB, 1)
    $seniorLabel = if ($seniorNameCodes -eq 'U+6797 U+79C0 U+5170') { "linxiulan [$seniorNameCodes]" } else { $seniorNameCodes }
    Write-Host ''
    Write-Host '=== backend exe smoke ===' -ForegroundColor Yellow
    Write-Host "exe        : $ExePath ($exeSizeMb MB)"
    Write-Host "temp dir   : $tempRoot"
    Write-Host "port       : $port"
    Write-Host "health     : $($health | ConvertTo-Json -Compress)"
    Write-Host "startup    : $startupSeconds s (cold start incl. one-file extraction + demo seed)"
    Write-Host "users      : senior #$($senior.id) $seniorLabel ($($senior.timezone)) | caregiver #$($caregiver.id) $($caregiver.display_name) (relationship $($caregiver.relationship_status))"
    Write-Host "consents   : $(@($consents.items).Count) rows, all allowed; topics=$($topics -join ',')"
    Write-Host "prefs      : greeting window $($preferences.greeting_start)-$($preferences.greeting_end) (demo mode), quiet $($preferences.quiet_start)-$($preferences.quiet_end)"
    Write-Host "digests    : senior 200 items=$(@($digests.items).Count) | caregiver 200 items=$(@($caregiverDigests.items).Count)"
    Write-Host "             (no digest is pre-seeded; the worker generates weekly digests)"
    Write-Host "tts        : $([math]::Round($tts.Length / 1KB)) KB of $($tts.ContentType) in $ttsSeconds s (real edge-tts synthesis through the frozen exe)"
    Write-Host "port clash : second copy exited 0, first backend still healthy"
    Write-Host "db file    : $dbFile"
    Write-Host "log file   : $logFile"
    Write-Host 'SMOKE OK: self-contained backend serves the demo world from a clean directory' -ForegroundColor Green
} catch {
    $failure = $_
} finally {
    Stop-SmokeProcess -Process $proc -ExecutablePath $exe
    Remove-Item -Path 'Env:ANCHOR_PORT' -ErrorAction SilentlyContinue
    foreach ($name in $savedEnv.Keys) { Set-Item -Path "Env:$name" -Value $savedEnv[$name] }
    if ($KeepTemp) {
        Write-Host "[smoke] kept temp dir: $tempRoot" -ForegroundColor DarkGray
    } else {
        Remove-Item -Recurse -Force $tempRoot -ErrorAction SilentlyContinue
    }
}

if ($failure) {
    Write-Host "SMOKE FAILED: $failure" -ForegroundColor Red
    exit 1
}
exit 0
