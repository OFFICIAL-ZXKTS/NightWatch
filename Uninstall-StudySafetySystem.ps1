<#
.SYNOPSIS
    Uninstaller for SleepSafe
#>

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Warning "Please run this script in an Administrator PowerShell window to remove the Scheduled Task."
    pause
    exit 1
}

Write-Host "Removing SleepSafe Scheduled Tasks..." -ForegroundColor Yellow
Unregister-ScheduledTask -TaskName "SleepSafeSentinel" -Confirm:$false -ErrorAction SilentlyContinue
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

$dataDir = "C:\ProgramData\SleepSafe"
if (Test-Path $dataDir) {
    Remove-Item -Path $dataDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "SleepSafe uninstalled successfully." -ForegroundColor Green
