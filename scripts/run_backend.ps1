param([int]$Port = 8077)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_common.ps1"

Push-Location $script:BackendDir
try {
    & $script:VenvPython -m uvicorn app.main:app --host 127.0.0.1 --port $Port --reload
} finally {
    Pop-Location
}
