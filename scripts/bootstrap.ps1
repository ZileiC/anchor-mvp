# Creates the local Python environment for the Anchor backend.
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_common.ps1"

Ensure-PythonVenv
Write-Host '[setup] python dependencies ready'

Push-Location $script:BackendDir
try {
    # Apply any pending SQL migrations to the configured database.
    $migrate = "from app.config import Settings; from app.db import Database; " +
               "db = Database(Settings.from_env().db_path); " +
               "print('[setup] migrations applied:', db.migrate() or 'none'); db.close()"
    & $script:VenvPython -c $migrate
    if ($LASTEXITCODE -ne 0) { throw 'database migration failed' }
} finally {
    Pop-Location
}

Write-Host ''
Write-Host 'Bootstrap complete.' -ForegroundColor Green
Write-Host '  backend : powershell -File scripts/run_backend.ps1'
Write-Host '  worker  : powershell -File scripts/run_worker.ps1'
Write-Host '  app     : powershell -File scripts/run_app.ps1'
