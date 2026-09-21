<#
.SYNOPSIS
    SleepSafe Study Break Button (v2.0)
.DESCRIPTION
    1. Sets Break Mode to ACTIVE in global C:\ProgramData\SleepSafe\break_state.json.
    2. Creates Desktop marker for visual feedback.
    3. Prevents accidental cancellation from double-clicking (debounce guard).
    4. Clicking again when returning toggles Break Mode OFF.
#>

$dataDir = "C:\ProgramData\SleepSafe"
if (-not (Test-Path $dataDir)) {
    New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
}

$stateFile = Join-Path $dataDir "break_state.json"
$desktopPath = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::Desktop)
if (-not (Test-Path $desktopPath)) {
    $desktopPath = Join-Path $env:USERPROFILE "Desktop"
}
$desktopMarker = Join-Path $desktopPath "break_marker.txt"
$wsh = New-Object -ComObject Wscript.Shell

# Read current state & debounce
$isActive = $false
$lastClick = [DateTime]::MinValue

if (Test-Path $stateFile) {
    try {
        $json = Get-Content $stateFile -Raw | ConvertFrom-Json
        $isActive = [bool]$json.Active
        if ($json.Timestamp) {
            $lastClick = [DateTime]$json.Timestamp
        }
    } catch {}
}

# Ignore clicks within 5 seconds to prevent double-click self-cancellation
if ($lastClick -gt [DateTime]::MinValue) {
    $diff = ((Get-Date) - $lastClick).TotalSeconds
    if ($diff -lt 5) {
        exit 0
    }
}

if ($isActive) {
    # TOGGLE OFF: User is back to study
    $state = @{
        Active = $false
        Timestamp = (Get-Date).ToString("o")
        Mode = "Working"
    } | ConvertTo-Json
    Set-Content -Path $stateFile -Value $state -Force

    if (Test-Path $desktopMarker) {
        Remove-Item -Path $desktopMarker -Force -ErrorAction SilentlyContinue
    }

    try { [System.Media.SystemSounds]::Asterisk.Play() } catch {}
    $msg = "BACK TO STUDY!`n`nBreak mode is now OFF.`nSleepSafe 30-minute idle shutdown protection is ARMED."
    $wsh.Popup($msg, 4, "SleepSafe", 64) | Out-Null
} else {
    # TOGGLE ON: User is taking a break
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $state = @{
        Active = $true
        Timestamp = (Get-Date).ToString("o")
        Mode = "OnBreak"
    } | ConvertTo-Json
    Set-Content -Path $stateFile -Value $state -Force

    $markerContent = @"
==================================================
           SLEEPSAFE: STUDY BREAK ACTIVE
Initiated at: $timestamp
Status: Auto-shutdown is PAUSED. PC stays ON.
==================================================
This marker signals to the SleepSafe background
sentinel that this break is intentional.
"@
    try {
        Set-Content -Path $desktopMarker -Value $markerContent -Force
    } catch {}

    try { [System.Media.SystemSounds]::Asterisk.Play() } catch {}
    $msg = "STUDY BREAK ACTIVATED!`n`nAuto-shutdown is PAUSED.`nYour PC will NOT shut down even after 30 mins."
    $wsh.Popup($msg, 4, "SleepSafe", 64) | Out-Null
}
