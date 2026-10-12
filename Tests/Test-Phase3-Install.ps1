<#
.SYNOPSIS
    Verifies the NightWatch install: scheduled task, shortcut, data dir, log.
.PARAMETER Quiet
    Suppress pass messages, only print failures.
#>
[CmdletBinding()]
param([switch]$Quiet)

$ErrorActionPreference = 'Stop'
$pass = 0; $fail = 0

function Test-Item {
    param($Name, [bool]$Cond, $Detail = "")
    $script:pass += if ($Cond) { 1 } else { 0 }
    $script:fail += if ($Cond) { 0 } else { 1 }
    if (-not $Quiet -or -not $Cond) {
        $icon = if ($Cond) { "PASS" } else { "FAIL" }
        $color = if ($Cond) { "Green" } else { "Red" }
        $detailStr = if ($Detail) { " - $Detail" } else { "" }
        Write-Host "[$icon] $Name$detailStr" -ForegroundColor $color
    }
}

Write-Host "=== Phase 3: Install verification ===" -ForegroundColor Cyan

# 1. Scheduled task
$task = Get-ScheduledTask -TaskName "NightWatchSentinel" -ErrorAction SilentlyContinue
Test-Item "Scheduled task 'NightWatchSentinel' exists" ($null -ne $task)

if ($task) {
    try {
        $info = Get-ScheduledTaskInfo $task -ErrorAction SilentlyContinue
        $nextRun = if ($info) { $info.NextRunTime } else { $null }
        Test-Item "Task has a next run time" ($nextRun -ne $null) "next at $nextRun"
    } catch {
        Test-Item "Task has a next run time" $false $_.Exception.Message
    }
    $runLevel = "$($task.Principal.RunLevel)"
    Test-Item "Task runs with highest privileges" ($runLevel -eq "Highest" -or $runLevel -like "*Highest*")
    Test-Item "Task logon type is InteractiveToken" `
        ($task.Principal.LogonType -eq [Microsoft.PowerShell.Cmdletization.GeneratedTypes.ScheduledTask.TaskLogonType]::InteractiveToken -or `
         "$($task.Principal.LogonType)" -like "*Interactive*")
}

# 2. Desktop shortcut
$shortcut = Join-Path ([System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::Desktop)) "Study Break.lnk"
Test-Item "Desktop shortcut 'Study Break.lnk' exists" (Test-Path $shortcut)

if (Test-Path $shortcut) {
    try {
        $ws = New-Object -ComObject WScript.Shell
        $sc = $ws.CreateShortcut($shortcut)
        $hasHotkey = $sc.Hotkey -eq "CTRL+ALT+B"
        $hasIcon = $sc.IconLocation -like "*icon.ico*"
        Test-Item "Shortcut has Ctrl+Alt+B hotkey" $hasHotkey "got '$($sc.Hotkey)'"
        Test-Item "Shortcut points to StudyBreak.ps1" ($sc.TargetPath -like "*powershell.exe*")
        Test-Item "Shortcut icon is the custom 3D icon" $hasIcon "got '$($sc.IconLocation)'"
    } catch {
        Test-Item "Shortcut properties readable" $false $_.Exception.Message
    }
}

# 3. Data directory
$dataDir = "C:\ProgramData\NightWatch"
Test-Item "Data directory '$dataDir' exists" (Test-Path $dataDir)

# 4. Log writability
$logFile = Join-Path $dataDir "mistake_detector.log"
$probe = Join-Path $dataDir "phase3_probe.tmp"
$wrote = $false
try {
    if (-not (Test-Path $dataDir)) { New-Item -ItemType Directory -Path $dataDir -Force | Out-Null }
    Add-Content -Path $probe -Value "x" -ErrorAction Stop
    Remove-Item $probe -Force -ErrorAction SilentlyContinue
    $wrote = $true
} catch {
    Write-Host "       (probe failed: $($_.Exception.Message))" -ForegroundColor DarkYellow
}
Test-Item "Data directory is writable" $wrote

# 5. Hibernation enabled
try {
    $hib = powercfg /availablesleepstates 2>&1
    Test-Item "Hibernation is enabled" ($hib -match "Hibernate")
} catch {
    Test-Item "Hibernation status checkable" $false $_.Exception.Message
}

# 6. bcdedit (boot beep suppression)
try {
    $bcd = bcdedit /enum "{default}" 2>&1 | Out-String
    Test-Item "Boot status policy is IgnoreAllFailures" ($bcd -match "ignoreallfailures")
} catch {
    Test-Item "bcdedit readable" $false $_.Exception.Message
}

Write-Host ""
Write-Host "Result: $pass passed, $fail failed" -ForegroundColor $(if ($fail -eq 0) { "Green" } else { "Red" })
exit $fail
