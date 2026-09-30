<#
.SYNOPSIS
    NightWatch Automated Mistake Detector & Idle Sentinel (v3.0)
.DESCRIPTION
    1. Measures TRUE physical keyboard/mouse idle time via Win32 GetLastInputInfo.
    2. Only acts if computer has been idle for AT LEAST 30 MINUTES (1800 seconds).
    3. Break state has a user-set DURATION and auto-expires when it elapses.
    4. Break state is bound to the OS boot session: if the PC was restarted or
       shut down, any break from the previous session is discarded.
       Sleep and hibernate do NOT reset boot uptime, so breaks survive those.
    5. Never modifies or deletes Desktop files, preventing desktop refresh/flicker.
    6. If 30-min idle is reached without a valid break:
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

# Current OS boot uptime in ms. Resets to ~0 on restart/shutdown, keeps
# increasing across sleep and hibernate. This is the boot-session fingerprint.
$currentUptimeMs = [long][Environment]::TickCount

$dataDir = "C:\ProgramData\NightWatch"
if (-not (Test-Path $dataDir)) {
    try { New-Item -ItemType Directory -Path $dataDir -Force | Out-Null } catch {}
}
$stateFile = Join-Path $dataDir "break_state.json"
$logFile = Join-Path $dataDir "mistake_detector.log"
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

# -----------------------------------------------------------------
# BREAK STATE RESOLUTION (single source of truth: break_state.json)
# A break is only honoured when BOTH hold:
#   a) it was created in the CURRENT boot session, and
#   b) its duration has not elapsed yet.
# -----------------------------------------------------------------
$isBreakActive = $false
$clearReason = $null
$json = $null

if (Test-Path $stateFile) {
    try {
        $json = Get-Content $stateFile -Raw | ConvertFrom-Json
    } catch { $json = $null }
}

if ($json -and [bool]$json.Active) {

    # (a) Boot-session check. Stored uptime greater than current uptime means
    # the machine rebooted after the break was created, so it is stale.
    # Sleep/hibernate keep uptime monotonic, so those breaks stay valid.
    if ($null -ne $json.BootUptimeMs) {
        $storedUptime = [long]$json.BootUptimeMs
        if ($storedUptime -gt $currentUptimeMs) {
            $isBreakActive = $false
            $clearReason = "PC was restarted or shut down since this break was set. Break discarded."
        }
    } else {
        # Legacy state with no boot fingerprint: cannot prove it is current.
        $isBreakActive = $false
        $clearReason = "Break state predates boot-session tracking. Break discarded."
    }

    # (b) Duration expiry check.
    if ($isBreakActive -and $json.ExpiresAt) {
        try {
            if ((Get-Date) -gt ([DateTime]$json.ExpiresAt)) {
                $isBreakActive = $false
                $clearReason = "Break duration of $($json.DurationMinutes) min has elapsed. Auto-disabled."
            }
        } catch {}
    }
}

# Persist the cleared state once, so later runs agree and the toggle button
# reflects reality. Guarded so this only happens on the transition.
if ($clearReason -and (Test-Path $stateFile)) {
    try {
        $cleared = @{ Active = $false; Timestamp = (Get-Date).ToString("o"); Mode = "AutoCleared" }
        $cleared | ConvertTo-Json | Set-Content -Path $stateFile -Force
        Add-Content -Path $logFile -Value "[$timestamp] BREAK CLEARED: $clearReason" -ErrorAction SilentlyContinue
    } catch {}
}

# IF COMPUTER IS NOT IDLE FOR 30 MINUTES -> EXIT IMMEDIATELY
# Does not touch any files, does not steal focus, 0% CPU impact.
if ($idleSeconds -lt $targetIdleSeconds) {
    exit 0
}

# -----------------------------------------------------------------
# 30 MINUTES OF TRUE INACTIVITY REACHED
# -----------------------------------------------------------------

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
