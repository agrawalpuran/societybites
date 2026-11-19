$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")
$targetDb = "societybites_incentive_integration_v2"
$previousDatabase = $env:DATABASE_URL
$previousDirect = $env:DIRECT_URL
$secure = Read-Host "Local postgres password for 127.0.0.1" -AsSecureString
$ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
try {
  $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
  if ([string]::IsNullOrEmpty($plain)) { throw "Local postgres password is required" }
  $encoded = [Uri]::EscapeDataString($plain)
  $url = "postgresql://postgres:${encoded}@127.0.0.1:5432/$targetDb"
  if ($url -match "(?i)supabase") { throw "Refusing a Supabase connection" }
  $parsed = [Uri]$url
  $database = [Uri]::UnescapeDataString($parsed.AbsolutePath.TrimStart("/"))
  if ($parsed.Query) { throw "Refusing a database URL with query parameters" }
  if ($parsed.Host -ne "127.0.0.1" -or $parsed.Port -ne 5432 -or $database -ne $targetDb) {
    throw "Refusing a database other than 127.0.0.1:5432/$targetDb"
  }
  $env:DATABASE_URL = $url
  $env:DIRECT_URL = $url
  & node "tests\incentive-rewards-v2.integration.js"
  exit $LASTEXITCODE
} finally {
  if ($ptr -ne [IntPtr]::Zero) {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
  }
  if ($null -eq $previousDatabase) {
    Remove-Item Env:DATABASE_URL -ErrorAction SilentlyContinue
  } else {
    $env:DATABASE_URL = $previousDatabase
  }
  if ($null -eq $previousDirect) {
    Remove-Item Env:DIRECT_URL -ErrorAction SilentlyContinue
  } else {
    $env:DIRECT_URL = $previousDirect
  }
}
