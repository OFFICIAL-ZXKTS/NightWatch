<#
.SYNOPSIS
    Study Break Button Script
.DESCRIPTION
    1. Creates 'break_marker.txt' on the user's Desktop.
    2. Immediately triggers deep Hibernation (saving RAM state to SSD and powering down).
#>

# 1. Resolve the Desktop path reliably (supports OneDrive redirection)
$desktopPath = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::Desktop)
if (-not (Test-Path -Path $desktopPath)) {
    $desktopPath = Join-Path $env:USERPROFILE "Desktop"
}

$markerPath = Join-Path $desktopPath "break_marker.txt"

# 2. Create the break marker file with timestamp
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$markerContent = @"
=========================================
INTENTIONAL STUDY BREAK ACTIVE
Initiated at: $timestamp
Laptop state: Hibernated
=========================================
This file indicates to the Idle Mistake Detector
that this break was intentional.
"@

try {
    Set-Content -Path $markerPath -Value $markerContent -Force -ErrorAction Stop
} catch {
    # Fallback to local profile Desktop if permission or path issue
    $fallbackPath = Join-Path $env:USERPROFILE "Desktop\break_marker.txt"
    Set-Content -Path $fallbackPath -Value $markerContent -Force
}

# 3. Enter Deep Hibernate immediately
# /h = Hibernate
shutdown.exe /h
