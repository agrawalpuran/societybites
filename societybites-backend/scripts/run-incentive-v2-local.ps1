param(
  [switch]$BlockedSuitesOnly,
  [switch]$PrepareRegression,
  [switch]$RetryFailures,
  [switch]$Phase3AOnly,
  [switch]$Acceptance,
  [switch]$Phase3Validation
)

$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")
$targetDb = "societybites_incentive_integration_v2"
$resultName = "societybites-v2-local-result.txt"
if ($BlockedSuitesOnly) { $resultName = "societybites-v2-blocked-suites.txt" }
if ($PrepareRegression) { $resultName = "societybites-v2-regression.txt" }
if ($RetryFailures) { $resultName = "societybites-v2-retry.txt" }
if ($Phase3AOnly) { $resultName = "societybites-v2-phase3a.txt" }
if ($Acceptance) { $resultName = "societybites-v2-acceptance.txt" }
if ($Phase3Validation) { $resultName = "societybites-v2-phase3-validation.txt" }
$result = Join-Path $env:TEMP $resultName
$previousDatabase = $env:DATABASE_URL
$previousDirect = $env:DIRECT_URL
$plain = ""
$ptr = [IntPtr]::Zero

function Write-Result([string]$line) {
  Add-Content -Path $result -Value $line
}

function Redact([string]$text) {
  if ([string]::IsNullOrEmpty($text)) { return "" }
  $safe = $text
  if (-not [string]::IsNullOrEmpty($plain)) {
    $safe = $safe.Replace($plain, "[redacted]")
    $encoded = [Uri]::EscapeDataString($plain)
    if (-not [string]::IsNullOrEmpty($encoded)) { $safe = $safe.Replace($encoded, "[redacted]") }
  }
  return ($safe -replace "(?i)postgresql://\S+", "postgresql://[redacted]")
}

function Invoke-Logged([string]$label, [scriptblock]$command) {
  Write-Result ("BEGIN " + $label)
  $previous = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  $output = & $command 2>&1 | Out-String
  $code = $LASTEXITCODE
  $ErrorActionPreference = $previous
  $safe = Redact $output
  if (-not [string]::IsNullOrWhiteSpace($safe)) { Write-Result $safe.TrimEnd() }
  Write-Result ("EXIT " + $label + " " + $code)
  return $code
}

Set-Content -Path $result -Value ("PROMPT_OPEN " + (Get-Date -Format o))
Write-Host "SocietyEats local validation"
Write-Host "Target: 127.0.0.1:5432/$targetDb"
Write-Host "Enter the local PostgreSQL password for the postgres role."
Write-Host "Do not enter the hosted database password. This value is not saved."
$secure = Read-Host "Local postgres password for 127.0.0.1" -AsSecureString
$ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
try {
  $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
  if ([string]::IsNullOrEmpty($plain)) { throw "Local postgres password is required" }
  $encoded = [Uri]::EscapeDataString($plain)
  $url = "postgresql://postgres:${encoded}@127.0.0.1:5432/$targetDb"
  if ($url -match "(?i)supabase|pooler") { throw "Refusing a Supabase connection" }
  $parsed = [Uri]$url
  $database = [Uri]::UnescapeDataString($parsed.AbsolutePath.TrimStart("/"))
  if ($parsed.Query) { throw "Refusing a database URL with query parameters" }
  if ($parsed.Host -ne "127.0.0.1" -or $parsed.Port -ne 5432 -or $database -ne $targetDb) {
    throw "Refusing a database other than 127.0.0.1:5432/$targetDb"
  }
  $env:DATABASE_URL = $url
  $env:DIRECT_URL = $url
  Write-Result "URL_ACCEPTED host=127.0.0.1 port=5432 db=$targetDb"

  $inspectCode = Invoke-Logged "inspect" { node "scripts\inspect-incentive-v2.js" }
  if ($inspectCode -ne 0) { throw "Read-only inspection failed" }
  $inspection = Get-Content $result -Raw
  if ($inspection -notmatch "IDENTITY db=$targetDb host=127\.0\.0\.1 port=5432") {
    throw "Inspection did not confirm the approved database"
  }
  if ($inspection -match "FLAGS_ENABLED yes") { throw "An incentive switch is enabled. Refusing writes." }
  if ($inspection -notmatch "LEDGER_TRIGGERS_MISSING none") { throw "A ledger trigger is missing or disabled. Refusing writes." }
  if ($inspection -match "LISTING_FIRST_PUBLISHED absent") { throw "Listing.firstPublishedAt is absent. Refusing writes." }
  foreach ($table in @("IncentiveCampaign", "IncentiveEvent", "IncentiveReward", "IncentiveLedgerEntry", "IncentiveSetting", "Coupon", "User", "Listing")) {
    if ($inspection -notmatch ("PUBLIC_TABLES .*" + [regex]::Escape($table))) {
      throw ("Required table is absent: " + $table)
    }
  }
  if ($inspection -notmatch "INSPECT_OK") { throw "Inspection did not finish" }
  Write-Result "MIGRATIONS_NOT_APPLIED schema objects are present. _prisma_migrations is not required for this run, and deploy was not used."

  if ($PrepareRegression -or $RetryFailures) {
    $env:SOCIETYBITES_V2_SEED = "1"
    $seedCode = Invoke-Logged "seed" { node "prisma\seed.js" }
    Remove-Item Env:SOCIETYBITES_V2_SEED -ErrorAction SilentlyContinue
    if ($seedCode -ne 0) { throw "Local seed failed" }
    $suites = if ($RetryFailures -and -not $PrepareRegression) {
      @(
        "order-lifecycle",
        "order-cancellation",
        "order-idempotency",
        "society-scoping",
        "preorder",
        "listing-catalog",
        "test-otp"
      )
    } else {
      @(
        "whatsapp-settings",
        "order-lifecycle",
        "order-cancellation",
        "order-reconciliation",
        "order-messages",
        "order-idempotency",
        "seller-payment-preference",
        "seller-order-history",
        "society-scoping",
        "cross-society-order",
        "preorder",
        "listing-catalog",
        "test-otp"
      )
    }
    foreach ($suite in $suites) {
      Invoke-Logged $suite { node ("tests\" + $suite + ".test.js") } | Out-Null
    }
    if (-not $RetryFailures -or $PrepareRegression) {
      Invoke-Logged "regression" { npm run test:regression } | Out-Null
    }
    Invoke-Logged "final-inspect" { node "scripts\inspect-incentive-v2.js" } | Out-Null
    Write-Result "RUN_FINISHED"
    return
  }

  if ($Phase3Validation) {
    $steps = @(
      @{ Name = "phase3a"; File = "tests\incentive-rewards-v2.integration.js" },
      @{ Name = "phase3-journeys"; File = "tests\incentive-phase3-journeys.js" },
      @{ Name = "acceptance"; File = "tests\incentive-acceptance-e2e.js" }
    )
    foreach ($step in $steps) {
      Invoke-Logged $step.Name { node $step.File } | Out-Null
      $checkpoint = Invoke-Logged ("identity-after-" + $step.Name) { node "scripts\inspect-incentive-v2.js" }
      if ($checkpoint -ne 0) { throw "Database identity changed after $($step.Name)" }
      $text = Get-Content $result -Raw
      $flagMatches = [regex]::Matches($text, "FLAGS_ENABLED (yes|no)")
      if ($flagMatches.Count -gt 0 -and $flagMatches[$flagMatches.Count - 1].Groups[1].Value -eq "yes") {
        throw "An incentive switch was left enabled after $($step.Name)"
      }
      $triggerMatches = [regex]::Matches($text, "LEDGER_TRIGGERS_MISSING (\S+)")
      if ($triggerMatches.Count -gt 0 -and $triggerMatches[$triggerMatches.Count - 1].Groups[1].Value -ne "none") {
        throw "A ledger trigger was left disabled after $($step.Name)"
      }
    }
    Write-Result "RUN_FINISHED"
    return
  }

  if ($Acceptance) {
    Invoke-Logged "acceptance" { node "tests\incentive-acceptance-e2e.js" } | Out-Null
    $identityCode = Invoke-Logged "identity-after-acceptance" { node "scripts\inspect-incentive-v2.js" }
    if ($identityCode -ne 0) { throw "Database identity changed after acceptance" }
    if ((Get-Content $result -Raw) -match "FLAGS_ENABLED yes") { throw "Acceptance left an incentive switch enabled" }
    Write-Result "RUN_FINISHED"
    return
  }

  if ($Phase3AOnly) {
    Invoke-Logged "phase3a" { node "tests\incentive-rewards-v2.integration.js" } | Out-Null
    $identityCode = Invoke-Logged "identity-after-phase3a" { node "scripts\inspect-incentive-v2.js" }
    if ($identityCode -ne 0) { throw "Database identity changed after Phase 3A" }
    Write-Result "RUN_FINISHED"
    return
  }

  if (-not $BlockedSuitesOnly) {
    Invoke-Logged "phase3a" { node "tests\incentive-rewards-v2.integration.js" } | Out-Null
    $identityCode = Invoke-Logged "identity-after-phase3a" { node "scripts\inspect-incentive-v2.js" --identity-only }
    if ($identityCode -ne 0) { throw "Database identity changed after Phase 3A" }
  }

  Invoke-Logged "whatsapp-settings" { node "tests\whatsapp-settings.test.js" } | Out-Null
  Invoke-Logged "payment-provider" { node "tests\payment-provider.test.js" } | Out-Null
  $identityCode = Invoke-Logged "identity-after-suites" { node "scripts\inspect-incentive-v2.js" --identity-only }
  if ($identityCode -ne 0) { throw "Database identity changed after the blocked suites" }

  if (-not $BlockedSuitesOnly) {
    Invoke-Logged "regression" { npm run test:regression } | Out-Null
  }
  Invoke-Logged "final-inspect" { node "scripts\inspect-incentive-v2.js" } | Out-Null
  Write-Result "RUN_FINISHED"
} catch {
  Write-Result ("STOPPED " + (Redact $_.Exception.Message))
  exit 1
} finally {
  if ($ptr -ne [IntPtr]::Zero) {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
  }
  $plain = ""
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
