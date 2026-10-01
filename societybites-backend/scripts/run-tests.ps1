# Runs backend test suites one at a time.
# Each suite keeps its Express server handle open after the last assertion, so
# node never exits on its own. Without the kill below, every run leaks a
# process that holds Prisma connections until the Supabase pooler is drained.
param(
  [string[]]$Tests,
  [int]$TimeoutSeconds = 120
)

if (-not $Tests -or $Tests.Count -eq 0) {
  $Tests = Get-ChildItem "$PSScriptRoot\..\tests\*.test.js" |
    ForEach-Object { $_.Name -replace '\.test\.js$', '' }
}

$root = Resolve-Path "$PSScriptRoot\.."
$failed = @()

foreach ($name in $Tests) {
  $log = Join-Path $env:TEMP "bt-$name.log"
  $proc = Start-Process -FilePath "node" `
    -ArgumentList "tests/$name.test.js" `
    -WorkingDirectory $root `
    -RedirectStandardOutput $log `
    -RedirectStandardError "$log.err" `
    -NoNewWindow -PassThru

  $exited = $proc.WaitForExit($TimeoutSeconds * 1000)
  if (-not $exited) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }

  $out = (Get-Content $log -Raw -ErrorAction SilentlyContinue) +
         (Get-Content "$log.err" -Raw -ErrorAction SilentlyContinue)
  # Suites report success in their own words, so treat a thrown error or an
  # empty run as the only failure signals.
  if ($out -match '(?m)^\s*(Error|AssertionError|\w*Error):' -or -not $out) {
    Write-Host "FAIL  $name"
    $failed += $name
  } else {
    Write-Host "PASS  $name"
  }

  # Suites spawn the API as a child; reap any that outlived their parent.
  Get-CimInstance Win32_Process -Filter "Name='node.exe'" |
    Where-Object { $_.CommandLine -like '*tests/*.test.js*' -or $_.CommandLine -match 'node\.exe" index\.js' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
  Start-Sleep -Seconds 2
}

if ($failed.Count -gt 0) {
  Write-Host ""
  Write-Host "Failed: $($failed -join ', ')"
  exit 1
}
Write-Host "All suites passed."
