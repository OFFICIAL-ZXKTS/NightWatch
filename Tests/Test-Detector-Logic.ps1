<#
.SYNOPSIS
    Tests the three break-validation branches of IdleMistakeDetector.ps1 by
    crafting state files that exercise each path.
.PARAMETER Case
    Expiry  - writes a state with ExpiresAt in the past; expect AutoCleared.
    Reboot  - writes a state with BootUptimeMs in the future; expect AutoCleared.
    Valid   - writes a state with both checks passing; expect unchanged.
    All     - runs all three in sequence.
.NOTES
    Exits with the number of failed cases. 0 = all good.
#>
[CmdletBinding()]
param([ValidateSet("Expiry","Reboot","Valid","All")][string]$Case = "All")

$ErrorActionPreference = 'Stop'

$repoRoot  = Split-Path -Parent $PSScriptRoot
$dataDir   = "C:\ProgramData\NightWatch"
$stateFile = Join-Path $dataDir "break_state.json"
$logFile   = Join-Path $dataDir "mistake_detector.log"
$tempLog   = Join-Path $env:TEMP "NightWatch.log"
$detector  = Join-Path $repoRoot "IdleMistakeDetector.ps1"

if (-not (Test-Path $detector)) {
    Write-Host "Detector not found at $detector" -ForegroundColor Red
    exit 2
}
if (-not (Test-Path $dataDir)) {
    New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
}

function Write-State($obj) {
    $obj | ConvertTo-Json -Depth 4 | Set-Content -Path $stateFile -Force
}

function Read-State {
    if (Test-Path $stateFile) { Get-Content $stateFile -Raw | ConvertFrom-Json } else { $null }
}

function Reset-Inactive {
    @{ Active = $false; Timestamp = (Get-Date).ToString("o"); Mode = "Working" } |
        ConvertTo-Json | Set-Content $stateFile -Force
}

# Returns @(lines, path) - the most recent log file the detector wrote to.
function Read-RecentLog {
    $primary = if (Test-Path $logFile) { Get-Item $logFile } else { $null }
    $temp    = if (Test-Path $tempLog) { Get-Item $tempLog } else { $null }
    $pick = $null
    if ($primary -and $temp) {
        $pick = if ($primary.LastWriteTime -gt $temp.LastWriteTime) { $primary } else { $temp }
    } elseif ($primary) {
        $pick = $primary
    } elseif ($temp) {
        $pick = $temp
    }
    if ($pick) { return @((Get-Content $pick.FullName), $pick.FullName) }
    return @(@(), $null)
}

# Test-Case prints "[PASS]/[FAIL]" lines, returns the number of FAILs, and
# also updates the script-scope $caseResults array so the per-case summary
# line at the end can be printed.
$script:caseResults = @()
function T($n, [bool]$c, $d = "") {
    $script:caseResults += [pscustomobject]@{ Name = $n; Pass = $c; Detail = $d }
    $icon  = if ($c) { "PASS" } else { "FAIL" }
    $color = if ($c) { "Green" } else { "Red" }
    $dstr  = if ($d)  { " - $d" } else { "" }
    Write-Host "[$icon] $n$dstr" -ForegroundColor $color
}

function Test-Case($name, $setupState) {
    Write-Host ""
    Write-Host "--- Case: $name ---" -ForegroundColor Cyan
    $script:caseResults = @()

    Reset-Inactive
    & $detector 2>&1 | Out-Null  # clear any prior state
    Reset-Inactive

    # Snapshot the most-recently-touched log so we can see what THIS run wrote.
    $snapPath = $null
    $primary  = if (Test-Path $logFile) { Get-Item $logFile } else { $null }
    $temp     = if (Test-Path $tempLog) { Get-Item $tempLog } else { $null }
    if ($primary -and $temp) {
        $snapPath = if ($primary.LastWriteTime -gt $temp.LastWriteTime) { $logFile } else { $tempLog }
    } elseif ($primary) { $snapPath = $logFile }
    elseif ($temp)     { $snapPath = $tempLog }
    $snapSize = if ($snapPath) { (Get-Item $snapPath).Length } else { 0 }

    # Craft and run
    $setupState | ConvertTo-Json -Depth 4 | Set-Content $stateFile -Force
    & $detector 2>&1 | Out-Null
    $after = Read-State

    # Read whatever the detector wrote during this run. Prefer the file we
    # snapshotted; fall back to whichever log has fresh content.
    $newLines = @()
    $wrotePath = $null
    if ($snapPath -and (Test-Path $snapPath)) {
        $currentSize = (Get-Item $snapPath).Length
        if ($currentSize -gt $snapSize) {
            $wrotePath = $snapPath
            $all = Get-Content $snapPath
            # Drop leading lines until we cross the snap size.
            $bytes = 0; $start = 0
            for ($i = 0; $i -lt $all.Count; $i++) {
                $bytes += [System.Text.Encoding]::UTF8.GetByteCount($all[$i]) + 2
                if ($bytes -gt $snapSize) { $start = $i; break }
            }
            if ($start -lt $all.Count) { $newLines = $all[$start..($all.Count - 1)] }
        }
    } else {
        $r = Read-RecentLog
        $newLines = $r[0]; $wrotePath = $r[1]
    }

    $expectActive = $false
    $expectMode = $null
    $expectLogContains = $null
    switch ($name) {
        "Expiry" {
            $expectActive = $false
            $expectMode = "AutoCleared"
            $expectLogContains = "has elapsed"
        }
        "Reboot" {
            $expectActive = $false
            $expectMode = "AutoCleared"
            $expectLogContains = "restarted or shut down"
        }
        "Valid" {
            $expectActive = $true
            $expectMode = "OnBreak"
            $expectLogContains = $null  # no clear line
        }
    }

    T "State.Active after run" ($after.Active -eq $expectActive) "got '$($after.Active)', expected '$expectActive'"
    T "State.Mode after run"   ($after.Mode -eq $expectMode) "got '$($after.Mode)', expected '$expectMode'"

    if ($expectLogContains) {
        $found = $newLines | Where-Object { $_ -like "*$expectLogContains*" } | Select-Object -First 1
        T "Log line contains '$expectLogContains'" ($null -ne $found) $(if ($found) { $found } else { "not found in $wrotePath" })
    } else {
        $clears = $newLines | Where-Object { $_ -like "*BREAK CLEARED*" }
        T "No BREAK CLEARED line for a valid break" ($null -eq $clears)
    }

    $passCount = ($script:caseResults | Where-Object { $_.Pass }).Count
    $failCount = ($script:caseResults | Where-Object { -not $_.Pass }).Count
    $color = if ($failCount -eq 0) { "Green" } else { "Red" }
    Write-Host "    Case result: $passCount passed, $failCount failed" -ForegroundColor $color
    return $failCount
}

# Build the three test states
$now  = Get-Date
$boot = [long][Environment]::TickCount

$expiryState = @{
    Active          = $true
    Timestamp       = $now.AddMinutes(-10).ToString("o")
    Mode            = "OnBreak"
    DurationMinutes = 30
    ExpiresAt       = $now.AddMinutes(-1).ToString("o")   # expired 1 min ago
    BootUptimeMs    = $boot                                 # current boot, so boot check passes
}

$rebootState = @{
    Active          = $true
    Timestamp       = $now.ToString("o")
    Mode            = "OnBreak"
    DurationMinutes = 30
    ExpiresAt       = $now.AddMinutes(30).ToString("o")    # valid expiry
    BootUptimeMs    = $boot + 99999999                       # simulate a previous OS session
}

$validState = @{
    Active          = $true
    Timestamp       = $now.ToString("o")
    Mode            = "OnBreak"
    DurationMinutes = 30
    ExpiresAt       = $now.AddMinutes(30).ToString("o")
    BootUptimeMs    = $boot                                 # current boot
}

$total = 0
switch ($Case) {
    "Expiry" { $total += Test-Case "Expiry" $expiryState }
    "Reboot" { $total += Test-Case "Reboot" $rebootState }
    "Valid"  { $total += Test-Case "Valid"  $validState }
    "All" {
        $total += Test-Case "Expiry" $expiryState
        $total += Test-Case "Reboot" $rebootState
        $total += Test-Case "Valid"  $validState
    }
}

# Always end in inactive state so the test is idempotent.
Reset-Inactive
Write-Host ""
Write-Host "Total: $total case(s) failed" -ForegroundColor $(if ($total -eq 0) { "Green" } else { "Red" })
exit $total
