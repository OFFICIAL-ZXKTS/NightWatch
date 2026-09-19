<#
.SYNOPSIS
    Automated One-Click Installer for Study Break & Idle Mistake Detector
.DESCRIPTION
    1. Enables Windows Hibernation (powercfg /hibernate on).
    2. Creates a clean 'Study Break' Desktop shortcut with an icon and hotkey (Ctrl+Alt+B).
    3. Registers the Windows 11 Scheduled Task with a 30-minute idle trigger and battery support.
#>

# Check for Administrator privileges
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Warning "Please run this script in an Administrator PowerShell window to configure Scheduled Tasks and Hibernation."
    Write-Host "Right-click PowerShell -> 'Run as Administrator', then execute this script again."
    pause
    exit 1
}

$scriptDir = $PSScriptRoot
if (-not $scriptDir) { $scriptDir = "C:\Users\diyaj\Downloads\Shutdown" }

$breakScriptPath = Join-Path $scriptDir "StudyBreak.ps1"
$idleScriptPath = Join-Path $scriptDir "IdleMistakeDetector.ps1"

Write-Host "======================================================" -ForegroundColor Cyan
Write-Host "  Installing Windows 11 Study Break & Safety System  " -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan

# 1. Enable Hibernation
Write-Host "`n[1/3] Enabling Windows Hibernation..." -ForegroundColor Yellow
try {
    powercfg /hibernate on
    Write-Host " -> Hibernation is enabled successfully." -ForegroundColor Green
} catch {
    Write-Warning " -> Failed to set powercfg /hibernate on: $_"
}

# 2. Create Desktop Shortcut
Write-Host "`n[2/3] Creating 'Study Break' Desktop Shortcut..." -ForegroundColor Yellow
$desktopPath = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::Desktop)
if (-not (Test-Path -Path $desktopPath)) {
    $desktopPath = Join-Path $env:USERPROFILE "Desktop"
}
$shortcutPath = Join-Path $desktopPath "Study Break.lnk"

try {
    $wshShell = New-Object -ComObject WScript.Shell
    $shortcut = $wshShell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = "powershell.exe"
    $shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$breakScriptPath`""
    $shortcut.WorkingDirectory = $scriptDir
    $shortcut.IconLocation = "shell32.dll,27" # Classic power/sleep icon
    $shortcut.Description = "Take an intentional Study Break (Hibernates PC and sets safety marker)"
    $shortcut.Hotkey = "Ctrl+Alt+B"
    $shortcut.Save()
    Write-Host " -> Shortcut created on Desktop: '$shortcutPath'" -ForegroundColor Green
    Write-Host " -> Shortcut key assigned: Ctrl + Alt + B" -ForegroundColor Green
} catch {
    Write-Warning " -> Failed to create shortcut: $_"
}

# 3. Register the 30-minute Idle Scheduled Task
Write-Host "`n[3/3] Registering Task Scheduler 'IdleMistakeDetector' (30 min idle)..." -ForegroundColor Yellow

$taskName = "IdleMistakeDetector"
$taskXml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>Detects accidental idle (falling asleep) after 30 minutes and executes a safe forced shutdown unless an intentional study break marker exists on the Desktop.</Description>
    <Author>StudySafetySystem</Author>
  </RegistrationInfo>
  <Triggers>
    <IdleTrigger>
      <Enabled>true</Enabled>
    </IdleTrigger>
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
    <IdleSettings>
      <Duration>PT30M</Duration>
      <WaitTimeout>PT2H</WaitTimeout>
      <StopOnIdleEnd>false</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <RunOnlyIfIdle>true</RunOnlyIfIdle>
    <DisallowStartOnRemoteAppSession>false</DisallowStartOnRemoteAppSession>
    <UseUnifiedSchedulingEngine>true</UseUnifiedSchedulingEngine>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT1H</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>powershell.exe</Command>
      <Arguments>-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$idleScriptPath`"</Arguments>
    </Exec>
  </Actions>
</Task>
"@

try {
    # Unregister existing task if present
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    Register-ScheduledTask -TaskName $taskName -Xml $taskXml -Force | Out-Null
    Write-Host " -> Task '$taskName' registered successfully in Task Scheduler!" -ForegroundColor Green
} catch {
    Write-Warning " -> Failed to register scheduled task: $_"
}

Write-Host "`n======================================================" -ForegroundColor Cyan
Write-Host "  Setup Complete! System is fully active.             " -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host "To test:"
Write-Host " 1. Click the 'Study Break' icon on your Desktop (or press Ctrl+Alt+B)."
Write-Host " 2. Laptop will hibernate, saving open tabs, and 'break_marker.txt' will appear on Desktop."
Write-Host " 3. If you leave PC idle for 30m without clicking Study Break, it will shut down cleanly."
