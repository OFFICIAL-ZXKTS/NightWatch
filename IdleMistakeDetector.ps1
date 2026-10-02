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

# 1b. Compile a high-volume alarm using the Win32 waveOut API.
# Console::Beep plays a quiet system tone that is easily missed when the user
# is asleep. waveOut lets us drive the audio device at full volume, so the
# warning is genuinely loud enough to wake someone.
if (-not ([System.Management.Automation.PSTypeName]'NightWatchLoudAlarm').Type) {
    Add-Type @'
using System;
using System.Runtime.InteropServices;

public class NightWatchLoudAlarm {
    const int WAVE_MAPPER = -1;
    const uint WAVE_FORMAT_PCM = 1;
    const uint WAVE_MAPPER_NO_SOUNDHANDLER_HACK = 0;

    [StructLayout(LayoutKind.Sequential)]
    public struct WAVEFORMATEX {
        public ushort wFormatTag;
        public ushort nChannels;
        public uint nSamplesPerSec;
        public uint nAvgBytesPerSec;
        public ushort nBlockAlign;
        public ushort wBitsPerSample;
        public ushort cbSize;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct WAVEHDR {
        public IntPtr lpData;
        public uint dwBufferLength;
        public uint dwBytesRecorded;
        public IntPtr dwUser;
        public uint dwFlags;
        public uint dwLoops;
        public IntPtr lpNext;
        public IntPtr reserved;
    }

    [DllImport("winmm.dll", CharSet = CharSet.Auto)]
    static extern int waveOutOpen(out IntPtr hWaveOut, int uDeviceID, ref WAVEFORMATEX lpFormat, IntPtr dwCallback, IntPtr dwInstance, uint dwFlags);

    [DllImport("winmm.dll")]
    static extern int waveOutPrepareHeader(IntPtr hWaveOut, ref WAVEHDR lpWaveOutHdr, uint uSize);

    [DllImport("winmm.dll")]
    static extern int waveOutWrite(IntPtr hWaveOut, ref WAVEHDR lpWaveOutHdr, uint uSize);

    [DllImport("winmm.dll")]
    static extern int waveOutUnprepareHeader(IntPtr hWaveOut, ref WAVEHDR lpWaveOutHdr, uint uSize);

    [DllImport("winmm.dll")]
    static extern int waveOutReset(IntPtr hWaveOut);

    [DllImport("winmm.dll")]
    static extern int waveOutClose(IntPtr hWaveOut);

    const uint WHDR_DONE = 0x00000001;
    const uint WAVEVOLUME_MAX = (uint)0xFFFFFFFF;

    [DllImport("winmm.dll")]
    static extern int waveOutSetVolume(IntPtr hWaveOut, uint dwVolume);

    /// <summary>Plays a full-volume square-wave tone. Returns false on failure.</summary>
    public static bool PlayTone(int frequency, int milliseconds) {
        IntPtr hWave = IntPtr.Zero;
        GCHandle pin = GCHandle.Alloc(IntPtr.Zero);
        try {
            WAVEFORMATEX fmt = new WAVEFORMATEX();
            fmt.wFormatTag = (ushort)WAVE_FORMAT_PCM;
            fmt.nChannels = 1;          // mono
            fmt.nSamplesPerSec = 44100; // CD-rate, so tones stay clean
            fmt.wBitsPerSample = 16;
            fmt.nBlockAlign = (ushort)(fmt.nChannels * fmt.wBitsPerSample / 8);
            fmt.nAvgBytesPerSec = fmt.nSamplesPerSec * fmt.nBlockAlign;
            fmt.cbSize = 0;

            if (waveOutOpen(out hWave, WAVE_MAPPER, ref fmt, IntPtr.Zero, IntPtr.Zero, 0) != 0)
                return false;

            // Drive the device to its maximum output level.
            waveOutSetVolume(hWave, WAVEVOLUME_MAX);

            int numSamples = (int)(fmt.nSamplesPerSec * (milliseconds / 1000.0));
            short[] buffer = new short[numSamples];

            // Square wave at full scale: far louder and far more attention
            // grabbing than the sine the system beep uses.
            int halfPeriod = (int)Math.Max(1L, (long)fmt.nSamplesPerSec / (frequency * 2));
            for (int i = 0; i < numSamples; i++) {
                buffer[i] = ((i / halfPeriod) % 2 == 0) ? (short)32767 : (short)-32768;
            }

            GCHandle b = GCHandle.Alloc(buffer, GCHandleType.Pinned);
            WAVEHDR hdr = new WAVEHDR();
            hdr.lpData = b.AddrOfPinnedObject();
            hdr.dwBufferLength = (uint)(numSamples * sizeof(short));
            hdr.dwBytesRecorded = 0;
            hdr.dwUser = IntPtr.Zero;
            hdr.dwFlags = 0;
            hdr.dwLoops = 0;
            hdr.lpNext = IntPtr.Zero;
            hdr.reserved = IntPtr.Zero;

            if (waveOutPrepareHeader(hWave, ref hdr, (uint)Marshal.SizeOf(typeof(WAVEHDR))) != 0) {
                b.Free();
                return false;
            }

            if (waveOutWrite(hWave, ref hdr, (uint)Marshal.SizeOf(typeof(WAVEHDR))) != 0) {
                waveOutUnprepareHeader(hWave, ref hdr, (uint)Marshal.SizeOf(typeof(WAVEHDR)));
                b.Free();
                return false;
            }

            // Block until the tone finishes so the buffer is not freed early.
            int waited = 0;
            while ((hdr.dwFlags & WHDR_DONE) == 0 && waited < milliseconds + 2000) {
                System.Threading.Thread.Sleep(20);
                waited += 20;
            }

            waveOutReset(hWave);
            waveOutUnprepareHeader(hWave, ref hdr, (uint)Marshal.SizeOf(typeof(WAVEHDR)));
            b.Free();
            return true;
        } catch {
            return false;
        } finally {
            if (hWave != IntPtr.Zero) {
                try { waveOutReset(hWave); } catch { }
                try { waveOutClose(hWave); } catch { }
            }
            try { if (pin.IsAllocated) pin.Free(); } catch { }
        }
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
    $isBreakActive = $true

    # (a) Boot-session check. Stored uptime greater than current uptime means
    # the machine rebooted after the break was created, so it is stale.
    # Sleep/hibernate keep uptime monotonic, so those breaks stay valid.
    if ($null -eq $json.BootUptimeMs) {
        # Legacy state with no boot fingerprint: cannot prove it is current.
        $isBreakActive = $false
        $clearReason = "Break state predates boot-session tracking. Break discarded."
    } else {
        $storedUptime = [long]$json.BootUptimeMs
        if ($storedUptime -gt $currentUptimeMs) {
            $isBreakActive = $false
            $clearReason = "PC was restarted or shut down since this break was set. Break discarded."
        }
    }

    # (b) Duration expiry check. Evaluated independently of (a) so a break is
    # still cleared for expiry even if the boot check already flagged it.
    if ($json.ExpiresAt) {
        try {
            $expiry = [DateTime]$json.ExpiresAt
            if ((Get-Date) -gt $expiry) {
                $isBreakActive = $false
                if (-not $clearReason) {
                    $clearReason = "Break duration of $($json.DurationMinutes) min has elapsed. Auto-disabled."
                }
            }
        } catch {
            # Unparseable expiry: treat the break as expired rather than trust it.
            $isBreakActive = $false
            if (-not $clearReason) {
                $clearReason = "Break expiry time unreadable. Break discarded for safety."
            }
        }
    }
}

# Persist the cleared state once, so later runs agree and the toggle button
# reflects reality. Guarded so this only happens on the transition.
# NOTE: the state write and the log append are deliberately SEPARATE try blocks.
# The log lives in ProgramData and can be locked/unwritable (e.g. while another
# instance holds it). If both shared one try, a failing log append would abort
# the block BEFORE the state was flushed, leaving a stale break "active" forever
# and silently swallowed by the catch.
if ($clearReason -and (Test-Path $stateFile)) {
    try {
        $cleared = @{ Active = $false; Timestamp = (Get-Date).ToString("o"); Mode = "AutoCleared" }
        $cleared | ConvertTo-Json | Set-Content -Path $stateFile -Force
    } catch {
        # Could not persist; treat the break as inactive for this run anyway.
    }
    try {
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
$beepCycles = 30 # 30 half-second tones = 30 seconds of continuous alarm

for ($i = 0; $i -lt $beepCycles; $i++) {
    # Check if user moved mouse or pressed any key
    $latestIdle = [Win32Idle]::GetIdleTimeMs() / 1000
    if ($latestIdle -lt 5) {
        # User moved mouse or pressed key! Cancel immediately!
        $aborted = $true
        break
    }

    # Loud, full-volume alarm. Alternate between two piercing tones so it
    # cuts through sleep and is impossible to mistake for a normal beep.
    $freq = if ($i % 2 -eq 0) { 1800 } else { 2400 }
    $played = $false
    try {
        $played = [NightWatchLoudAlarm]::PlayTone($freq, 500)
    } catch {}

    if (-not $played) {
        # Fall back to the system beep if waveOut is unavailable.
        try {
            [Console]::Beep($freq, 500)
        } catch {
            try { [System.Media.SystemSounds]::Exclamation.Play() } catch {}
        }
    }
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
