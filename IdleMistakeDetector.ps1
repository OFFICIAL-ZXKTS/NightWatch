<#
.SYNOPSIS
    SleepSafe Automated Mistake Detector & Idle Sentinel (v2.0)
.DESCRIPTION
    1. Measures TRUE physical keyboard/mouse idle time via Win32 GetLastInputInfo.
    2. Only acts if computer has been idle for AT LEAST 30 MINUTES (1800 seconds).
    3. Checks if Study Break mode is active:
       - IF BREAK ACTIVE: Skips shutdown. PC stays on safely.
       - IF NO BREAK (Fell asleep):
         * Plays 30 seconds of loud warning BEEPS.
         * If user touches mouse or keyboard during the beeps, shutdown is CANCELLED!
         * If no activity for 30s, cleanly shuts down to protect battery & SSD.
#>

# 1. Compile Win32 LastInputInfo if not already compiled
#    (Uses Environment.TickCount64 so it does not wrap at ~24.8 days like
#     Environment.TickCount does on Windows PowerShell 5.1.)
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
        long now = Environment.TickCount64;
        long then = lii.dwTime;
        long idle = now - then;
        if (idle < 0) idle = 0; // safety; should never happen
        return (uint)idle;
    }
}
'@
}

# 2. Get TRUE physical idle time in seconds
$idleMs = [Win32Idle]::GetIdleTimeMs()
$idleSeconds = [Math]::Floor($idleMs / 1000)
$targetIdleSeconds = 1800 # 30 minutes exact

# Logs live in C:\ProgramData\SleepSafe so they don't leak into the repo folder.
$dataDir = "C:\ProgramData\SleepSafe"
if (-not (Test-Path $dataDir)) {
    try { New-Item -ItemType Directory -Path $dataDir -Force | Out-Null } catch {}
}
$logFile = Join-Path $dataDir "mistake_detector.log"
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

# 3. Check break status from global state & desktop markers
$stateFile = Join-Path $dataDir "break_state.json"
$isBreakActive = $false

if (Test-Path $stateFile) {
    try {
        $json = Get-Content $stateFile -Raw | ConvertFrom-Json
        $isBreakActive = [bool]$json.Active
    } catch {}
}

# Also scan possible desktop locations for marker
$desktopPaths = @(
    (Join-Path ([System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::Desktop)) "break_marker.txt"),
    (Join-Path $env:USERPROFILE "Desktop\break_marker.txt")
)
if ($env:OneDrive) {
    $desktopPaths += (Join-Path $env:OneDrive "Desktop\break_marker.txt")
}
$userDirs = Get-ChildItem -Path "C:\Users" -Directory -ErrorAction SilentlyContinue | 
            Where-Object { $_.Name -notmatch '^(Public|Default|Default User|All Users)$' }
foreach ($dir in $userDirs) {
    $desktopPaths += (Join-Path $dir.FullName "Desktop\break_marker.txt")
    $desktopPaths += (Join-Path $dir.FullName "OneDrive\Desktop\break_marker.txt")
}
foreach ($p in ($desktopPaths | Select-Object -Unique)) {
    if (Test-Path -Path $p) {
        $isBreakActive = $true
        break
    }
}

# CHECK 1: If user returned and is actively typing/moving mouse (idle < 30 seconds), automatically clear break!
if ($idleSeconds -lt 30 -and $isBreakActive) {
    if (Test-Path $stateFile) {
        @{ Active = $false; Timestamp = (Get-Date).ToString("o"); Mode = "AutoResumed" } | ConvertTo-Json | Set-Content -Path $stateFile -Force
    }
    foreach ($p in ($desktopPaths | Select-Object -Unique)) {
        if (Test-Path -Path $p) {
            Remove-Item -Path $p -Force -ErrorAction SilentlyContinue
        }
    }
    exit 0
}

# CHECK 2: Has the computer been idle for AT LEAST 30 MINUTES?
if ($idleSeconds -lt $targetIdleSeconds) {
    # Not yet 30 minutes! NEVER shut down prematurely!
    exit 0
}

# -----------------------------------------------------------------
# COMPUTER HAS BEEN IDLE FOR 30+ MINUTES
# -----------------------------------------------------------------

if ($isBreakActive) {
    # Intentional Break Active -> SKIP SHUTDOWN
    $logMsg = "[$timestamp] INTENTIONAL BREAK ACTIVE: Computer has been idle for $([Math]::Round($idleSeconds/60,1)) mins, but user is on break. Shutdown suppressed."
    Add-Content -Path $logFile -Value $logMsg -ErrorAction SilentlyContinue
    exit 0
} else {
    # ACCIDENTAL SLEEP DETECTED: No break signal & 30m idle!
    $logMsg = "[$timestamp] ACCIDENTAL SLEEP DETECTED: Computer idle for $([Math]::Round($idleSeconds/60,1)) mins without break signal. Starting 30-second warning beeps..."
    Add-Content -Path $logFile -Value $logMsg -ErrorAction SilentlyContinue

    # -----------------------------------------------------------------
    # 30-SECOND AUDIBLE WARNING BEEP COUNTDOWN
    # -----------------------------------------------------------------
    $aborted = $false
    $beepCycles = 15 # 15 cycles of 2 seconds = 30 seconds total warning

    for ($i = 0; $i -lt $beepCycles; $i++) {
        # Check if user moved mouse or pressed any key
        $latestIdle = [Win32Idle]::GetIdleTimeMs() / 1000
        if ($latestIdle -lt 5) {
            # User moved mouse or hit a key! Abort shutdown!
            $aborted = $true
            break
        }

        # Beep warning sound through speakers
        try {
            [Console]::Beep(1000, 250)
            Start-Sleep -Milliseconds 150
            [Console]::Beep(1400, 350)
        } catch {
            try { [System.Media.SystemSounds]::Exclamation.Play() } catch {}
        }

        Start-Sleep -Milliseconds 1250
    }

    if ($aborted) {
        $logMsg = "[$timestamp] SHUTDOWN CANCELLED: User activity detected during warning beeps. PC stays awake."
        Add-Content -Path $logFile -Value $logMsg -ErrorAction SilentlyContinue
        try { [System.Media.SystemSounds]::Asterisk.Play() } catch {}
        exit 0
    }

    # 30-second beeping finished with NO user activity -> User is asleep!
    $logMsg = "[$timestamp] EXECUTING FORCED SHUTDOWN: 30-second warning beeps ignored. Shutting down cleanly."
    Add-Content -Path $logFile -Value $logMsg -ErrorAction SilentlyContinue

    # Execute clean forced shutdown
    shutdown.exe /s /f /t 0
}
