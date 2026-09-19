<#
.SYNOPSIS
    Automated Mistake Detector (Idle Watcher)
.DESCRIPTION
    Runs via Windows Task Scheduler when laptop is idle for 30 minutes.
    - If break_marker.txt exists: User initiated break intentionally -> deletes marker and leaves PC running.
    - If break_marker.txt does not exist: User fell asleep / left unattended -> executes clean forced shutdown.
#>

# 1. Gather all potential Desktop paths (supports standard Desktop, OneDrive redirection, and SYSTEM task execution)
$candidatePaths = [System.Collections.Generic.List[string]]::new()

# Current user environment Desktop
$currentDesktop = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::Desktop)
if ($currentDesktop) {
    $candidatePaths.Add((Join-Path $currentDesktop "break_marker.txt"))
}

# Standard user profile desktop
if ($env:USERPROFILE) {
    $candidatePaths.Add((Join-Path $env:USERPROFILE "Desktop\break_marker.txt"))
}

# OneDrive environment desktop
if ($env:OneDrive) {
    $candidatePaths.Add((Join-Path $env:OneDrive "Desktop\break_marker.txt"))
}

# In case Task Scheduler runs under SYSTEM or Local Service, scan user profiles
$userDirs = Get-ChildItem -Path "C:\Users" -Directory -ErrorAction SilentlyContinue | 
            Where-Object { $_.Name -notmatch '^(Public|Default|Default User|All Users)$' }

foreach ($dir in $userDirs) {
    $candidatePaths.Add((Join-Path $dir.FullName "Desktop\break_marker.txt"))
    $candidatePaths.Add((Join-Path $dir.FullName "OneDrive\Desktop\break_marker.txt"))
}

# 2. Check if any marker file exists
$foundMarker = $null
foreach ($path in ($candidatePaths | Select-Object -Unique)) {
    if (Test-Path -Path $path) {
        $foundMarker = $path
        break
    }
}

# 3. Optional logging for verification & peace of mind
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $scriptDir) { $scriptDir = "C:\Users\diyaj\Downloads\Shutdown" }
$logFile = Join-Path $scriptDir "mistake_detector.log"
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

if ($foundMarker) {
    # -------------------------------------------------------------
    # INTENTIONAL BREAK DETECTED
    # -------------------------------------------------------------
    # Marker exists: The user went on a break intentionally.
    # Delete the marker file and leave the laptop alone.
    try {
        Remove-Item -Path $foundMarker -Force -ErrorAction SilentlyContinue
    } catch {
        # ignore if locked
    }
    
    $logMsg = "[$timestamp] INTENTIONAL BREAK: Found marker at '$foundMarker'. Deleted marker. Laptop left running as intended."
    Add-Content -Path $logFile -Value $logMsg -ErrorAction SilentlyContinue
    exit 0
} else {
    # -------------------------------------------------------------
    # MISTAKE DETECTED (USER FELL ASLEEP)
    # -------------------------------------------------------------
    # No break marker exists after 30 minutes of complete inactivity.
    # Force a clean shutdown immediately to protect battery and SSD.
    $logMsg = "[$timestamp] ACCIDENTAL SLEEP DETECTED: No break marker found after 30 mins of idle time. Executing clean forced shutdown."
    Add-Content -Path $logFile -Value $logMsg -ErrorAction SilentlyContinue

    # Clean forced shutdown:
    # /s = shutdown
    # /f = force close any hung or open apps
    # /t 0 = execute immediately (0-second countdown)
    shutdown.exe /s /f /t 0
}
