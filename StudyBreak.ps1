<#
.SYNOPSIS
    Study Break Signal Button (SleepSafe)
.DESCRIPTION
    Signals that you are on an intentional break.
    - Creates 'break_marker.txt' on Desktop so 30-min auto-shutdown is PAUSED.
    - Does NOT force sleep or hibernate mode—your PC stays on and active.
    - Clicking it again when you return toggles Break Mode OFF.
#>

# 1. Resolve true Desktop path (supports OneDrive folder redirection)
$desktopPath = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::Desktop)
if (-not (Test-Path -Path $desktopPath)) {
    $desktopPath = Join-Path $env:USERPROFILE "Desktop"
}

$markerPath = Join-Path $desktopPath "break_marker.txt"
$wsh = New-Object -ComObject Wscript.Shell

# 2. Toggle Break Mode
if (Test-Path -Path $markerPath) {
    # Already on break -> Toggle OFF (Back to study)
    try {
        Remove-Item -Path $markerPath -Force -ErrorAction SilentlyContinue
    } catch {}
    
    $wsh.Popup("📚 Back to Study!`n`nBreak mode is now OFF. 30-minute idle shutdown protection is RE-ARMED.", 3, "SleepSafe", 64) | Out-Null
} else {
    # Start break -> Toggle ON (Pause 30-min shutdown)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $markerContent = @"
=========================================
INTENTIONAL STUDY BREAK ACTIVE
Initiated: $timestamp
Status: Auto-shutdown PAUSED. Laptop stays ON.
=========================================
"@
    try {
        Set-Content -Path $markerPath -Value $markerContent -Force -ErrorAction Stop
    } catch {
        $fallbackPath = Join-Path $env:USERPROFILE "Desktop\break_marker.txt"
        Set-Content -Path $fallbackPath -Value $markerContent -Force
    }

    # Notify user with a 3-second popup (laptop does NOT sleep/hibernate)
    $wsh.Popup("☕ Study Break Activated!`n`nSignal sent: Auto-shutdown is PAUSED.`nYour PC will NOT shut down even after 30 mins.", 4, "SleepSafe", 64) | Out-Null
}
