<#
.SYNOPSIS
    NightWatch Study Break Button (v3.2)
.DESCRIPTION
    1. Asks how long the break should last BEFORE enabling it (duration picker).
    2. Enables the break with an explicit expiry time and a boot-session stamp.
    3. The break auto-disables itself once the duration elapses, so there is no
       need to click again to turn it off.
    4. Clicking the button WHILE a break is running offers to end it early.
    5. State lives only in C:\ProgramData\NightWatch\break_state.json.
       Nothing is written to the Desktop.
#>

$dataDir = "C:\ProgramData\NightWatch"
if (-not (Test-Path $dataDir)) {
    New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
}
$stateFile = Join-Path $dataDir "break_state.json"

# Boot-session fingerprint: uptime in ms. Resets on restart/shutdown,
# keeps growing across sleep/hibernate.
$bootUptimeMs = [long][Environment]::TickCount

Add-Type -AssemblyName System.Windows.Forms | Out-Null
Add-Type -AssemblyName System.Drawing | Out-Null

[System.Windows.Forms.Application]::EnableVisualStyles()

# Palette
$bg        = [System.Drawing.Color]::FromArgb(24, 26, 33)
$panel     = [System.Drawing.Color]::FromArgb(34, 37, 46)
$fg        = [System.Drawing.Color]::FromArgb(238, 240, 245)
$muted     = [System.Drawing.Color]::FromArgb(150, 156, 170)
$accent    = [System.Drawing.Color]::FromArgb(94, 160, 255)
$danger    = [System.Drawing.Color]::FromArgb(226, 96, 96)
$line      = [System.Drawing.Color]::FromArgb(58, 62, 74)

# Layout constants
$PAD      = 24
$FORM_W   = 440
$LBL_H    = 26
$BTN_H    = 40
$ROW_GAP  = 10

# Build a form with DPI scaling disabled so nothing is rescaled twice.
function New-BaseForm {
    param([string]$Title, [int]$Height)
    $f = New-Object System.Windows.Forms.Form
    $f.Text = $Title
    $f.ClientSize = New-Object System.Drawing.Size($FORM_W, $Height)
    $f.StartPosition = "CenterScreen"
    $f.FormBorderStyle = "FixedDialog"
    $f.MaximizeBox = $false
    $f.MinimizeBox = $false
    $f.TopMost = $true
    $f.BackColor = $bg
    $f.ForeColor = $fg
    # Critical: without this, Windows rescales every coordinate on a
    # non-100% DPI display and controls end up overlapping or misaligned.
    $f.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
    return $f
}

# Label with a height derived from the font, so tall text cannot overflow
# into whatever sits below it.
function New-Label {
    param($Text, [float]$Size, $Color, [bool]$Bold, [int]$X, [int]$Y, [int]$W = ($FORM_W - 2 * $PAD))
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $Text
    $style = if ($Bold) { [System.Drawing.FontStyle]::Bold } else { [System.Drawing.FontStyle]::Regular }
    $l.Font = New-Object System.Drawing.Font("Segoe UI", $Size, $style)
    $l.ForeColor = $Color
    $l.BackColor = $bg
    $l.Location = New-Object System.Drawing.Point($X, $Y)
    # ~1.65 line height plus padding is enough for Segoe UI at any of our sizes.
    $h = [int][Math]::Ceiling($Size * 1.65) + 6
    $l.Size = New-Object System.Drawing.Size($W, $h)
    return $l
}

function New-Button {
    param($Text, $Color, $BorderColor, [int]$X, [int]$Y, [int]$W = 0, [bool]$AccentFont = $false)
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $Text
    $b.Height = $BTN_H
    if ($W -gt 0) { $b.Width = $W }
    $b.Location = New-Object System.Drawing.Point($X, $Y)
    $b.FlatStyle = "Flat"
    $b.FlatAppearance.BorderSize = 1
    $b.FlatAppearance.BorderColor = $(if ($BorderColor) { $BorderColor } else { $Color })
    $b.BackColor = $Color
    $b.ForeColor = $fg
    $style = if ($AccentFont) { [System.Drawing.FontStyle]::Bold } else { [System.Drawing.FontStyle]::Regular }
    $b.Font = New-Object System.Drawing.Font("Segoe UI", 10, $style)
    $b.UseVisualStyleBackColor = $false
    $b.AutoSize = $false
    return $b
}

# -----------------------------------------------------------------
# Read current state, applying the SAME validity rules as the detector
# so the button never offers to cancel a break that is already gone.
# -----------------------------------------------------------------
$isActive = $false
$expiresAt = $null
$durationMinutes = 0

if (Test-Path $stateFile) {
    try {
        $json = Get-Content $stateFile -Raw | ConvertFrom-Json
        $isActive = [bool]$json.Active
        if ($isActive) {
            $valid = $true
            # Break must come from the current boot session.
            if ($null -eq $json.BootUptimeMs -or [long]$json.BootUptimeMs -gt $bootUptimeMs) {
                $valid = $false
            }
            # And must not have expired. Checked independently of the boot test
            # so a restart and an expiry are both caught regardless of order.
            if ($valid -and $json.ExpiresAt) {
                try {
                    if ((Get-Date) -gt ([DateTime]$json.ExpiresAt)) { $valid = $false }
                } catch { $valid = $false }
            }
            $isActive = $valid
            if ($isActive) {
                if ($json.DurationMinutes) { $durationMinutes = [int]$json.DurationMinutes }
                if ($json.ExpiresAt) { try { $expiresAt = [DateTime]$json.ExpiresAt } catch {} }
            }
        }
    } catch {}
}

function Save-Inactive {
    $state = @{
        Active = $false
        Timestamp = (Get-Date).ToString("o")
        Mode = "Working"
    } | ConvertTo-Json
    Set-Content -Path $stateFile -Value $state -Force
}

# -----------------------------------------------------------------
# BREAK IS ALREADY RUNNING -> offer to end it early
# -----------------------------------------------------------------
if ($isActive) {
    if (-not $expiresAt) { $expiresAt = (Get-Date).AddMinutes($durationMinutes) }
    $remaining = [int][Math]::Ceiling(($expiresAt - (Get-Date)).TotalMinutes)
    if ($remaining -lt 0) { $remaining = 0 }

    $dlg = New-BaseForm -Title "NightWatch" -Height 236
    $y = $PAD

    $dlg.Controls.Add((New-Label "STUDY BREAK IS ACTIVE" 10 $muted $true $PAD $y)); $y += 24
    $dlg.Controls.Add((New-Label "Auto-shutdown is paused." 13 $fg $false $PAD $y)); $y += 30
    $dlg.Controls.Add((New-Label "Ends at  $($expiresAt.ToString('HH:mm:ss'))" 12 $accent $true $PAD $y)); $y += 28
    $dlg.Controls.Add((New-Label "$durationMinutes min break  |  $remaining min remaining" 10 $muted $false $PAD $y)); $y += 30

    $btnW = [int](($FORM_W - 3 * $PAD) / 2)
    $btnKeep = New-Button "Keep break" $panel $line $PAD $y $btnW
    $btnKeep.ForeColor = $muted
    $btnKeep.Add_Click({ $script:EndNow = $false; $dlg.Close() })
    $dlg.Controls.Add($btnKeep)

    $btnEnd = New-Button "End break now" $danger $danger ($PAD + $btnW + $PAD) $y $btnW
    $btnEnd.Add_Click({ $script:EndNow = $true; $dlg.Close() })
    $dlg.Controls.Add($btnEnd)

    $script:EndNow = $false
    $dlg.AcceptButton = $btnEnd
    $dlg.CancelButton = $btnKeep
    $dlg.ShowDialog() | Out-Null
    $dlg.Dispose()

    if ($script:EndNow) {
        Save-Inactive
        try { [System.Media.SystemSounds]::Asterisk.Play() } catch {}
        [System.Windows.Forms.MessageBox]::Show(
            "Break ended early.`n`n30-minute idle shutdown protection is ARMED.",
            "NightWatch", "OK", "Information") | Out-Null
    }
    exit 0
}

# -----------------------------------------------------------------
# DURATION PICKER
# -----------------------------------------------------------------
$form = New-BaseForm -Title "NightWatch - Study Break" -Height 300
$y = $PAD
$form.Controls.Add((New-Label "How long is your study break?" 15 $fg $true $PAD $y)); $y += 32
$form.Controls.Add((New-Label "Paused for this long, then re-arms by itself." 9 $muted $false $PAD $y)); $y += 28

$script:ChosenMinutes = 0

# Live preview, placed under the preset row with room to breathe.
$previewY = $y + $BTN_H + $ROW_GAP
$preview = New-Label "" 10 $accent $true $PAD $previewY
$form.Controls.Add($preview)

function Update-Preview {
    param([int]$Minutes)
    $end = (Get-Date).AddMinutes($Minutes)
    $preview.Text = "Auto-off at  $($end.ToString('HH:mm:ss'))    ($Minutes min from now)"
}

# Preset buttons in one row
$presets = @(15, 30, 40, 60)
$gap = 8
$btnW = [int](($FORM_W - 2 * $PAD - $gap * ($presets.Count - 1)) / $presets.Count)
$x = $PAD
foreach ($m in $presets) {
    $b = New-Button "$m min" $panel $accent $x $y $btnW $true
    $b.Tag = $m
    $b.Add_Click({
        $script:ChosenMinutes = [int]$this.Tag
        $form.Close()
    })
    $form.Controls.Add($b)
    $x += $btnW + $gap
}
$y = $previewY + 30

$form.Controls.Add((New-Label "Custom (1-1440 min)" 9 $muted $false $PAD $y)); $y += 22

$num = New-Object System.Windows.Forms.NumericUpDown
$num.Minimum = 1
$num.Maximum = 1440
$num.Value = 45
$num.Size = New-Object System.Drawing.Size(110, $BTN_H)
$num.Location = New-Object System.Drawing.Point($PAD, $y)
$num.BackColor = $panel
$num.ForeColor = $fg
$form.Controls.Add($num)

$btnStartCustom = New-Button "Start custom break" $panel $accent ($PAD + 118) ($y - 6) 190
$btnStartCustom.Add_Click({
    $script:ChosenMinutes = [int]$num.Value
    $form.Close()
})
$form.Controls.Add($btnStartCustom)
$y += $BTN_H + $ROW_GAP

$btnCancel = New-Button "Cancel" $panel $line ($FORM_W - $PAD - 130) $y 130
$btnCancel.ForeColor = $muted
$btnCancel.Add_Click({ $script:ChosenMinutes = 0; $form.Close() })
$form.Controls.Add($btnCancel)

$form.AcceptButton = $btnStartCustom
$form.CancelButton = $btnCancel
Update-Preview -Minutes 30
$form.ShowDialog() | Out-Null
$form.Dispose()

$minutes = [int]$script:ChosenMinutes
if ($minutes -le 0) {
    exit 0
}

# -----------------------------------------------------------------
# Enable the break with an explicit expiry and boot fingerprint
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

try { [System.Media.SystemSounds]::Asterisk.Play() } catch {}

$done = New-BaseForm -Title "NightWatch" -Height 224
$y = $PAD
$done.Controls.Add((New-Label "STUDY BREAK ACTIVATED" 15 $accent $true $PAD $y)); $y += 34
$done.Controls.Add((New-Label "$minutes minute break - auto-shutdown is PAUSED." 11 $fg $false $PAD $y)); $y += 28
$done.Controls.Add((New-Label "Auto-off at $($expiresAt.ToString('HH:mm:ss'))" 12 $fg $true $PAD $y)); $y += 28
$done.Controls.Add((New-Label "It turns itself off - no need to click again." 9 $muted $false $PAD $y)); $y += 32

$btnOk = New-Button "Got it" $accent $accent ($FORM_W - $PAD - 130) $y 130 $true
$btnOk.Add_Click({ $done.Close() })
$done.Controls.Add($btnOk)
$done.AcceptButton = $btnOk
$done.CancelButton = $btnOk
$done.ShowDialog() | Out-Null
$done.Dispose()
