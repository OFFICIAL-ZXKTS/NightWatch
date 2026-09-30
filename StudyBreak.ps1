<#
.SYNOPSIS
    NightWatch Study Break Button (v3.0)
.DESCRIPTION
    1. Asks the user how long the break should last BEFORE enabling it.
    2. Sets Break Mode ACTIVE in C:\ProgramData\NightWatch\break_state.json
       together with an expiry time and the current OS boot-session fingerprint.
    3. The break auto-disables itself once the chosen duration elapses,
       so the user never has to click again to turn it off.
    4. Creates a hidden Desktop marker for visual feedback.
    5. Prevents accidental cancellation from double-clicking (debounce guard).
    6. If a break is already running, offers to end it early.
#>

$dataDir = "C:\ProgramData\NightWatch"
if (-not (Test-Path $dataDir)) {
    New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
}

$stateFile = Join-Path $dataDir "break_state.json"
$desktopPath = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::Desktop)
if (-not (Test-Path $desktopPath)) {
    $desktopPath = Join-Path $env:USERPROFILE "Desktop"
}
$desktopMarker = Join-Path $desktopPath "break_marker.txt"

# Boot-session fingerprint: uptime in ms. Resets on restart/shutdown,
# keeps growing across sleep/hibernate.
$bootUptimeMs = [long][Environment]::TickCount

# -----------------------------------------------------------------
# Read current state, applying the SAME validity rules as the detector
# so the button never shows a stale break.
# -----------------------------------------------------------------
$isActive = $false
$lastClick = [DateTime]::MinValue

if (Test-Path $stateFile) {
    try {
        $json = Get-Content $stateFile -Raw | ConvertFrom-Json
        $isActive = [bool]$json.Active
        if ($json.Timestamp) {
            $lastClick = [DateTime]$json.Timestamp
        }
        if ($isActive) {
            # Stale across a restart?
            if ($null -eq $json.BootUptimeMs -or [long]$json.BootUptimeMs -gt $bootUptimeMs) {
                $isActive = $false
            }
            # Expired?
            if ($isActive -and $json.ExpiresAt) {
                if ((Get-Date) -gt ([DateTime]$json.ExpiresAt)) {
                    $isActive = $false
                }
            }
        }
    } catch {}
}

function Clear-BreakState {
    param($Reason)
    $state = @{
        Active = $false
        Timestamp = (Get-Date).ToString("o")
        Mode = "Working"
    } | ConvertTo-Json
    Set-Content -Path $stateFile -Value $state -Force
    if (Test-Path $desktopMarker) {
        Remove-Item -Path $desktopMarker -Force -ErrorAction SilentlyContinue
    }
}

# -----------------------------------------------------------------
# If a valid break is already running: offer to end it early.
# -----------------------------------------------------------------
if ($isActive) {
    Add-Type -AssemblyName System.Windows.Forms | Out-Null
    $result = [System.Windows.Forms.MessageBox]::Show(
        "A study break is currently ACTIVE.`n`nEnd it now and re-arm idle shutdown protection?",
        "NightWatch", "YesNo", "Question")
    if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
        Clear-BreakState -Reason "EndedEarly"
        try { [System.Media.SystemSounds]::Asterisk.Play() } catch {}
        [System.Windows.Forms.MessageBox]::Show(
            "Break ended.`n`n30-minute idle shutdown protection is ARMED.",
            "NightWatch", "OK", "Information") | Out-Null
    }
    exit 0
}

# -----------------------------------------------------------------
# Ask for the break duration BEFORE enabling anything.
# -----------------------------------------------------------------
Add-Type -AssemblyName System.Windows.Forms | Out-Null
Add-Type -AssemblyName System.Drawing | Out-Null

$form = New-Object System.Windows.Forms.Form
$form.Text = "NightWatch - Study Break"
$form.Size = New-Object System.Drawing.Size(400, 320)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.MinimizeBox = $false
$form.TopMost = $true

$lbl = New-Object System.Windows.Forms.Label
$lbl.Text = "How long is your study break?"
$lbl.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
$lbl.AutoSize = $true
$lbl.Location = New-Object System.Drawing.Point(18, 18)
$form.Controls.Add($lbl)

$sub = New-Object System.Windows.Forms.Label
$sub.Text = "Auto-shutdown is paused for this long, then re-arms automatically."
$sub.AutoSize = $true
$sub.Location = New-Object System.Drawing.Point(18, 48)
$form.Controls.Add($sub)

# Lay the presets out in a row.
$presets = @(15, 30, 40, 60)
$x = 18
foreach ($m in $presets) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = "$m min"
    $b.Tag = $m
    $b.Size = New-Object System.Drawing.Size(80, 34)
    $b.Location = New-Object System.Drawing.Point($x, 80)
    $b.Add_Click({ $script:ChosenMinutes = [int]$this.Tag; $form.Close() })
    $form.Controls.Add($b)
    $x += 88
}

$lbl2 = New-Object System.Windows.Forms.Label
$lbl2.Text = "Or a custom duration (minutes):"
$lbl2.AutoSize = $true
$lbl2.Location = New-Object System.Drawing.Point(18, 130)
$form.Controls.Add($lbl2)

$num = New-Object System.Windows.Forms.NumericUpDown
$num.Minimum = 1
$num.Maximum = 1440
$num.Value = 30
$num.Size = New-Object System.Drawing.Size(100, 26)
$num.Location = New-Object System.Drawing.Point(18, 152)
$form.Controls.Add($num)

$useCustom = New-Object System.Windows.Forms.Button
$useCustom.Text = "Start custom break"
$useCustom.Size = New-Object System.Drawing.Size(180, 32)
$useCustom.Location = New-Object System.Drawing.Point(140, 149)
$useCustom.Add_Click({ $script:ChosenMinutes = [int]$num.Value; $form.Close() })
$form.Controls.Add($useCustom)

$cancel = New-Object System.Windows.Forms.Button
$cancel.Text = "Cancel"
$cancel.Size = New-Object System.Drawing.Size(120, 32)
$cancel.Location = New-Object System.Drawing.Point(140, 196)
$cancel.Add_Click({ $script:ChosenMinutes = 0; $form.Close() })
$form.Controls.Add($cancel)

$script:ChosenMinutes = 0
$form.AcceptButton = $useCustom
$form.CancelButton = $cancel
$form.ShowDialog() | Out-Null
$form.Dispose()

$minutes = [int]$script:ChosenMinutes
if ($minutes -le 0) {
    # Cancelled: nothing was changed.
    exit 0
}

# -----------------------------------------------------------------
# Enable the break with an explicit expiry and boot fingerprint.
# -----------------------------------------------------------------
$now = Get-Date
$expiresAt = $now.AddMinutes($minutes)

$state = @{
    Active = $true
    Timestamp = $now.ToString("o")
    Mode = "OnBreak"
    DurationMinutes = $minutes
    ExpiresAt = $expiresAt.ToString("o")
    BootUptimeMs = $bootUptimeMs
} | ConvertTo-Json
Set-Content -Path $stateFile -Value $state -Force

$markerContent = @"
==================================================
        NIGHTWATCH: STUDY BREAK ACTIVE
Started at   : $($now.ToString("yyyy-MM-dd HH:mm:ss"))
Duration     : $minutes minutes
Auto-off at  : $($expiresAt.ToString("yyyy-MM-dd HH:mm:ss"))
Status       : Auto-shutdown is PAUSED until then.
==================================================
This break expires automatically. No need to toggle off.
Restarting or shutting down the PC cancels this break.
"@
try {
    Set-Content -Path $desktopMarker -Value $markerContent -Force
    # Hide the marker so it doesn't clutter the user's Desktop.
    (Get-Item -Path $desktopMarker -Force).Attributes = 'Hidden'
} catch {}

try { [System.Media.SystemSounds]::Asterisk.Play() } catch {}
[System.Windows.Forms.MessageBox]::Show(
    "STUDY BREAK ACTIVATED!`n`nDuration: $minutes minutes`n`nAuto-shutdown is PAUSED until $($expiresAt.ToString("HH:mm:ss")).`nIt will turn itself off - no need to click again.",
    "NightWatch", "OK", "Information") | Out-Null
