param([switch]$Once)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_common.ps1"

Push-Location $script:BackendDir
try {
    if ($Once) { & $script:VenvPython -m app.worker --once } else { & $script:VenvPython -m app.worker }
} finally {
    Pop-Location
}
