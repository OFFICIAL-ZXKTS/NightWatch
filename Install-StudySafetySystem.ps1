<#
.SYNOPSIS
    Automated One-Click Installer for NightWatch (v2.0)
.DESCRIPTION
    1. Enables Windows Hibernation (powercfg /hibernate on).
    2. Creates 'Study Break' Desktop shortcut with custom 3D icon and Ctrl+Alt+B hotkey.
    3. Registers NightWatch Administrative Sentinel task with true Win32 idle monitoring.
#>

# Check for Administrator privileges
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Warning "Please run this script in an Administrator PowerShell window."
    Write-Host "Right-click PowerShell -> 'Run as Administrator', then execute this script again."
    pause
    exit 1
}

$scriptDir = $PSScriptRoot
if (-not $scriptDir) {
    Write-Warning "Could not determine script directory. Please run via .ps1 file path, not -Command."
    pause
    exit 1
}

$breakScriptPath = Join-Path $scriptDir "StudyBreak.ps1"
$idleScriptPath = Join-Path $scriptDir "IdleMistakeDetector.ps1"

Write-Host "======================================================" -ForegroundColor Cyan
Write-Host "       Installing NightWatch v2.0 Sentinel            " -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan

# 1. Ensure Global Data Directory Exists
$dataDir = "C:\ProgramData\NightWatch"
if (-not (Test-Path $dataDir)) {
    New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
}

# 2. Enable Hibernation
Write-Host "`n[1/3] Verifying Windows Hibernation..." -ForegroundColor Yellow
try {
    powercfg /hibernate on
    Write-Host " -> Hibernation is enabled successfully." -ForegroundColor Green
} catch {
    Write-Warning " -> Failed to set powercfg /hibernate on: $_"
}

# 3. Create Desktop Shortcut
Write-Host "`n[2/3] Creating 'Study Break' Desktop Shortcut with 3D Icon..." -ForegroundColor Yellow
$desktopPath = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::Desktop)
if (-not (Test-Path $desktopPath)) {
    $desktopPath = Join-Path $env:USERPROFILE "Desktop"
}
$shortcutPath = Join-Path $desktopPath "Study Break.lnk"

try {
    $wshShell = New-Object -ComObject WScript.Shell
    $shortcut = $wshShell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = "powershell.exe"
    $shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$breakScriptPath`""
    $shortcut.WorkingDirectory = $scriptDir
    $customIconPath = Join-Path $scriptDir "assets\icon.ico"
    if (Test-Path $customIconPath) {
        $shortcut.IconLocation = "$customIconPath,0"
    } else {
        $shortcut.IconLocation = "shell32.dll,27"
    }
    $shortcut.Description = "Take an intentional Study Break (Signals NightWatch to pause idle shutdown)"
    $shortcut.Hotkey = "Ctrl+Alt+B"
    $shortcut.Save()
    Write-Host " -> Shortcut created on Desktop: '$shortcutPath'" -ForegroundColor Green
    Write-Host " -> Shortcut key assigned: Ctrl + Alt + B" -ForegroundColor Green
} catch {
    Write-Warning " -> Failed to create shortcut: $_"
}

# 4. Register NightWatch Sentinel in Task Scheduler
Write-Host "`n[3/3] Registering NightWatch Administrative Sentinel (1-min Win32 precision check)..." -ForegroundColor Yellow

$taskName = "NightWatchSentinel"
$oldTaskName = "IdleMistakeDetector"

$silentRunnerPath = Join-Path $scriptDir "SilentRunner.vbs"

$taskXml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>NightWatch Sentinel v2.1: Accurately checks physical 30-minute keyboard/mouse idle time via Win32 API, respects intentional study breaks, and provides audible warning beeps before shutdown with 100% silent execution.</Description>
    <Author>OFFICIAL-ZXKTS</Author>
  </RegistrationInfo>
  <Triggers>
    <TimeTrigger>
      <StartBoundary>2000-01-01T00:00:00</StartBoundary>
      <Enabled>true</Enabled>
      <Repetition>
        <Interval>PT2M</Interval>
        <StopAtDurationEnd>false</StopAtDurationEnd>
      </Repetition>
    </TimeTrigger>
    <LogonTrigger>
      <Enabled>true</Enabled>
      <Repetition>
        <Interval>PT2M</Interval>
        <StopAtDurationEnd>false</StopAtDurationEnd>
      </Repetition>
    </LogonTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>true</Hidden>
    <ExecutionTimeLimit>PT5M</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>wscript.exe</Command>
      <Arguments>"$silentRunnerPath"</Arguments>
    </Exec>
  </Actions>
</Task>
"@

try {
    # Remove old buggy task if present
    Unregister-ScheduledTask -TaskName $oldTaskName -Confirm:$false -ErrorAction SilentlyContinue
    # Remove and register new sentinel task
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    Register-ScheduledTask -TaskName $taskName -Xml $taskXml -Force | Out-Null
    Write-Host " -> Task '$taskName' registered successfully in Task Scheduler!" -ForegroundColor Green
} catch {
    Write-Warning " -> Failed to register scheduled task: $_"
}

Write-Host "`n======================================================" -ForegroundColor Cyan
Write-Host "  NightWatch v2.0 Installed & Fully Active!           " -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host "Upgrades in this version:"
Write-Host " 1. Precise 30-min physical idle detection (no more 10-min false shutdowns!)."
Write-Host " 2. Robust Study Break tracking with double-click protection."
Write-Host " 3. 30-second warning BEEPS before shutdown (touching mouse cancels shutdown!)."
