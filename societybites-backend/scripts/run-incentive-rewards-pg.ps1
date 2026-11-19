$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")
$secure = Read-Host "Local postgres password for 127.0.0.1" -AsSecureString
$ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
try {
  $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
  $encoded = [Uri]::EscapeDataString($plain)
  $url = "postgresql://postgres:${encoded}@127.0.0.1:5432/societybites_incentive_foundation"
  $env:DATABASE_URL = $url
  $env:DIRECT_URL = $url
  & node "tests\incentive-rewards-pg.integration.js"
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
  & node "tests\incentive-rewards-coupon-pg.integration.js"
  exit $LASTEXITCODE
} finally {
  if ($ptr -ne [IntPtr]::Zero) {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
  }
  Remove-Item Env:DATABASE_URL -ErrorAction SilentlyContinue
  Remove-Item Env:DIRECT_URL -ErrorAction SilentlyContinue
}
