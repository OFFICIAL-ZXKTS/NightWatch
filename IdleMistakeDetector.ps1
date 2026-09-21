<#
.SYNOPSIS
    SleepSafe Automated Mistake Detector & Idle Sentinel (v2.1)
.DESCRIPTION
    1. Measures TRUE physical keyboard/mouse idle time via Win32 GetLastInputInfo.
    2. Only acts if computer has been idle for AT LEAST 30 MINUTES (1800 seconds).
    3. Never modifies or deletes Desktop files, preventing desktop icon refresh/flicker.
    4. If 30-min idle is reached without break mode:
       - Plays 30 seconds of warning beeps.
       - Moving mouse or pressing any key cancels shutdown immediately.
#>

# 1. Compile Win32 LastInputInfo if not already loaded
if (-not ([System.Management.Automation.PSTypeName]'Win32Idle').Type) {
    Add-Type @'
using System;
using System.Runtime.InteropServices;

public class Win32Idle {
    [StructLayout(LayoutKind.Sequential)]
    public struct LASTINPUTINFO {
        public uint cbSize;
        public uint dwTime;
    }

    [DllImport("user32.dll")]
    public static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);

    public static uint GetIdleTimeMs() {
        LASTINPUTINFO lii = new LASTINPUTINFO();
        lii.cbSize = (uint)Marshal.SizeOf(lii);
        if (!GetLastInputInfo(ref lii)) return 0;
        return (uint)Environment.TickCount - lii.dwTime;
    }
}
'@
}

# 2. Get true physical idle time in seconds
$idleMs = [Win32Idle]::GetIdleTimeMs()
$idleSeconds = [Math]::Floor($idleMs / 1000)
$targetIdleSeconds = 1800 # 30 minutes exact

# IF COMPUTER IS NOT IDLE FOR 30 MINUTES -> EXIT IMMEDIATELY
# Does not touch any files, does not steal focus, 0% CPU impact.
if ($idleSeconds -lt $targetIdleSeconds) {
    exit 0
}

# -----------------------------------------------------------------
# 30 MINUTES OF TRUE INACTIVITY REACHED
# -----------------------------------------------------------------

$dataDir = "C:\ProgramData\SleepSafe"
$logFile = Join-Path $dataDir "mistake_detector.log"
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

# Check if break mode is currently active (Read-only check)
$stateFile = Join-Path $dataDir "break_state.json"
$isBreakActive = $false

if (Test-Path $stateFile) {
    try {
        $json = Get-Content $stateFile -Raw | ConvertFrom-Json
        $isBreakActive = [bool]$json.Active
        
        # Auto-expire break mode if it has been active for more than 6 hours
        if ($isBreakActive -and $json.Timestamp) {
            $ageHours = ((Get-Date) - [DateTime]$json.Timestamp).TotalHours
            if ($ageHours -gt 6) {
                $isBreakActive = $false
            }
        }
    } catch {}
}

# Also check for Desktop marker existence (Read-only check)
if (-not $isBreakActive) {
    $desktopMarker = Join-Path ([System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::Desktop)) "break_marker.txt"
    if (Test-Path $desktopMarker) {
        $isBreakActive = $true
    }
}

if ($isBreakActive) {
    # Intentional break is active: DO NOT SHUT DOWN.
    # Leave laptop alone and do not touch any desktop files.
    $logMsg = "[$timestamp] INTENTIONAL BREAK: Computer idle for $([Math]::Round($idleSeconds/60,1)) mins, but break is active. Shutdown skipped."
    Add-Content -Path $logFile -Value $logMsg -ErrorAction SilentlyContinue
    exit 0
}

# -----------------------------------------------------------------
# ACCIDENTAL SLEEP DETECTED: 30-SECOND WARNING BEEP COUNTDOWN
# -----------------------------------------------------------------
$logMsg = "[$timestamp] ACCIDENTAL SLEEP: 30 mins idle reached without break signal. Starting warning beeps..."
Add-Content -Path $logFile -Value $logMsg -ErrorAction SilentlyContinue

$aborted = $false
$beepCycles = 15 # 15 cycles of 2 seconds = 30 seconds

for ($i = 0; $i -lt $beepCycles; $i++) {
    # Check if user moved mouse or pressed any key
    $latestIdle = [Win32Idle]::GetIdleTimeMs() / 1000
    if ($latestIdle -lt 5) {
        # User moved mouse or pressed key! Cancel immediately!
        $aborted = $true
        break
    }

    # Sound warning beep through speakers
    try {
        [Console]::Beep(1000, 250)
        Start-Sleep -Milliseconds 100
        [Console]::Beep(1400, 300)
    } catch {
        try { [System.Media.SystemSounds]::Exclamation.Play() } catch {}
    }

    Start-Sleep -Milliseconds 1350
}

if ($aborted) {
    $logMsg = "[$timestamp] SHUTDOWN CANCELLED: Activity detected during warning beeps. PC stays awake."
    Add-Content -Path $logFile -Value $logMsg -ErrorAction SilentlyContinue
    try { [System.Media.SystemSounds]::Asterisk.Play() } catch {}
    exit 0
}

# Warning beeps expired with zero input -> Clean forced shutdown
$logMsg = "[$timestamp] SHUTTING DOWN: Warning beeps expired without response. PC protecting battery & SSD."
Add-Content -Path $logFile -Value $logMsg -ErrorAction SilentlyContinue

shutdown.exe /s /f /t 0
