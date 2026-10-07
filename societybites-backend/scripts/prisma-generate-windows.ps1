# Stops Node processes that load the Prisma query engine from this repo, then runs prisma generate.
# Use when you see EPERM on query_engine-windows.dll.node (common with npm start or hung tests).

$ErrorActionPreference = "Stop"
$backendRoot = Split-Path -Parent $PSScriptRoot
$clientDir = Join-Path $backendRoot "node_modules\.prisma\client"

Get-CimInstance Win32_Process -Filter "name = 'node.exe'" |
  Where-Object { $_.CommandLine -match "societybites-backend|index\.js|seller-terms|fssai-compliance" } |
  ForEach-Object {
    Write-Host "Stopping node PID $($_.ProcessId)"
    Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
  }

Start-Sleep -Seconds 2

if (Test-Path $clientDir) {
  Remove-Item (Join-Path $clientDir "query_engine-windows.dll.node") -Force -ErrorAction SilentlyContinue
  Remove-Item (Join-Path $clientDir "query_engine-windows.dll.node.tmp*") -Force -ErrorAction SilentlyContinue
}

Set-Location $backendRoot
npx prisma generate
if ($LASTEXITCODE -ne 0) {
  Write-Host ""
  Write-Host "If EPERM persists: pause OneDrive sync for this folder, close other terminals running npm start, then run this script again."
  exit $LASTEXITCODE
}

Write-Host "Prisma client generated. You can run: npm start"
