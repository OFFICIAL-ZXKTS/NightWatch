<#
.SYNOPSIS
    Uninstaller for Study Break & Idle Mistake Detector
#>

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Warning "Please run this script in an Administrator PowerShell window to remove the Scheduled Task."
    pause
    exit 1
}

Write-Host "Removing Scheduled Task 'IdleMistakeDetector'..." -ForegroundColor Yellow
Unregister-ScheduledTask -TaskName "IdleMistakeDetector" -Confirm:$false -ErrorAction SilentlyContinue

$desktopPath = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::Desktop)
$shortcut = Join-Path $desktopPath "Study Break.lnk"
if (Test-Path $shortcut) {
    Remove-Item $shortcut -Force -ErrorAction SilentlyContinue
    Write-Host "Removed Desktop shortcut." -ForegroundColor Green
}

$marker = Join-Path $desktopPath "break_marker.txt"
if (Test-Path $marker) {
    Remove-Item $marker -Force -ErrorAction SilentlyContinue
}

Write-Host "System uninstalled successfully." -ForegroundColor Green
