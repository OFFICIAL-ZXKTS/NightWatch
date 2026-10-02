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
$PAD      = 22
$FORM_W   = 440
$BTN_H    = 42

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

# A single-column TableLayoutPanel. Label rows are AutoSize, so a row grows
# to fit its text instead of using a guessed pixel height. That makes overlap
# structurally impossible no matter what font size or DPI is in play.
function New-Stack {
    $t = New-Object System.Windows.Forms.TableLayoutPanel
    $t.Dock = "Fill"
    $t.ColumnCount = 1
    $t.RowCount = 0
    $t.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100))) | Out-Null
    $t.Padding = New-Object System.Windows.Forms.Padding($PAD, $PAD, $PAD, $PAD)
    $t.BackColor = $bg
    $t.Margin = New-Object System.Windows.Forms.Padding(0)
    return $t
}

# Append a row and return its index.
function Add-Row {
    param($Stack, [string]$Type = "Auto", $Value = 0)
    switch ($Type) {
        "Abs"  { $Stack.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, [single]$Value))) | Out-Null }
        "Fill" { $Stack.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100))) | Out-Null }
        default{ $Stack.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize))) | Out-Null }
    }
    $Stack.RowCount = $Stack.RowStyles.Count
    return $Stack.RowCount - 1
}

# Auto-sizing label. Height is delegated to the row, so it can never be wrong.
function New-Label {
    param($Text, [float]$Size, $Color, [bool]$Bold, [int]$BottomMargin = 4)
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $Text
    $style = if ($Bold) { [System.Drawing.FontStyle]::Bold } else { [System.Drawing.FontStyle]::Regular }
    $l.Font = New-Object System.Drawing.Font("Segoe UI", $Size, $style)
    $l.ForeColor = $Color
    $l.BackColor = $bg
    $l.AutoSize = $true
    $l.Dock = "Fill"
    $l.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, $BottomMargin)
    return $l
}

function New-Button {
    param($Text, $Color, $BorderColor, [int]$W, [bool]$AccentFont = $false)
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $Text
    $b.Dock = "Fill"
    $b.Margin = New-Object System.Windows.Forms.Padding(0)
    $b.FlatStyle = "Flat"
    $b.FlatAppearance.BorderSize = 1
    $b.FlatAppearance.BorderColor = $(if ($BorderColor) { $BorderColor } else { $Color })
    $b.BackColor = $Color
    $b.ForeColor = $fg
    $style = if ($AccentFont) { [System.Drawing.FontStyle]::Bold } else { [System.Drawing.FontStyle]::Regular }
    $b.Font = New-Object System.Drawing.Font("Segoe UI", 10, $style)
    $b.UseVisualStyleBackColor = $false
    $b.AutoSize = $false
    $b.MinimumSize = New-Object System.Drawing.Size($W, $BTN_H)
    return $b
}

# Horizontal row of equal-width buttons.
function New-ButtonRow {
    param([int[]]$Items, $Color, $BorderColor, [bool]$AccentFont = $false, [int]$Gap = 8, [int]$MinW = 0)
    $t = New-Object System.Windows.Forms.TableLayoutPanel
    $t.Dock = "Fill"
    $t.ColumnCount = $Items.Count
    $t.RowCount = 1
    for ($i = 0; $i -lt $Items.Count; $i++) {
        $t.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, [single](100 / $Items.Count)))) | Out-Null
    }
    $t.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100))) | Out-Null
    $t.BackColor = $bg
    $t.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 0)
    for ($i = 0; $i -lt $Items.Count; $i++) {
        $b = New-Button ([string]$Items[$i]) $Color $BorderColor $MinW $AccentFont
        $b.Margin = New-Object System.Windows.Forms.Padding(($(if ($i -eq 0) { 0 } else { $Gap })), 0, $(if ($i -eq $Items.Count - 1) { 0 } else { 0 }), 0)
        $t.Controls.Add($b, $i, 0)
    }
    return $t
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

    $dlg = New-BaseForm -Title "NightWatch" -Height 250
    $st = New-Stack
    $dlg.Controls.Add($st) | Out-Null

    $r = Add-Row $st; $st.Controls.Add((New-Label "STUDY BREAK IS ACTIVE" 10 $muted $true 6), 0, $r)
    $r = Add-Row $st; $st.Controls.Add((New-Label "Auto-shutdown is paused." 13 $fg $false 6), 0, $r)
    $r = Add-Row $st; $st.Controls.Add((New-Label "Ends at  $($expiresAt.ToString('HH:mm:ss'))" 12 $accent $true 6), 0, $r)
    $r = Add-Row $st; $st.Controls.Add((New-Label "$durationMinutes min break  |  $remaining min remaining" 10 $muted $false 12), 0, $r)
    $r = Add-Row $st "Fill"
    $r = Add-Row $st "Abs" $BTN_H

    $btnKeep = New-Button "Keep break" $panel $line 0
    $btnKeep.ForeColor = $muted
    $btnKeep.Margin = New-Object System.Windows.Forms.Padding(0, 0, 6, 0)
    $btnKeep.Add_Click({ $script:EndNow = $false; $dlg.Close() })

    $btnEnd = New-Button "End break now" $danger $danger 0
    $btnEnd.Margin = New-Object System.Windows.Forms.Padding(6, 0, 0, 0)
    $btnEnd.Add_Click({ $script:EndNow = $true; $dlg.Close() })

    # Two equal halves side by side.
    $split = New-Object System.Windows.Forms.TableLayoutPanel
    $split.Dock = "Fill"
    $split.ColumnCount = 2
    $split.RowCount = 1
    $split.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50))) | Out-Null
    $split.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50))) | Out-Null
    $split.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100))) | Out-Null
    $split.BackColor = $bg
    $split.Margin = New-Object System.Windows.Forms.Padding(0)
    $split.Controls.Add($btnKeep, 0, 0)
    $split.Controls.Add($btnEnd, 1, 0)
    $st.Controls.Add($split, 0, $r)

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
$form = New-BaseForm -Title "NightWatch - Study Break" -Height 320
$st = New-Stack
$form.Controls.Add($st) | Out-Null

$r = Add-Row $st; $st.Controls.Add((New-Label "How long is your study break?" 15 $fg $true 6), 0, $r)
$r = Add-Row $st; $st.Controls.Add((New-Label "Paused for this long, then re-arms by itself." 9 $muted $false 14), 0, $r)

$script:ChosenMinutes = 0

# Preset buttons in one row
$r = Add-Row $st "Abs" $BTN_H
$presets = @(15, 30, 40, 60)
$presetRow = New-Object System.Windows.Forms.TableLayoutPanel
$presetRow.Dock = "Fill"
$presetRow.ColumnCount = $presets.Count
$presetRow.RowCount = 1
$presetRow.BackColor = $bg
$presetRow.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 10)
for ($i = 0; $i -lt $presets.Count; $i++) {
    $presetRow.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 25))) | Out-Null
    $b = New-Button "$($presets[$i]) min" $panel $accent 0 $true
    $b.Margin = New-Object System.Windows.Forms.Padding($(if ($i -eq 0) { 0 } else { 4 }), 0, $(if ($i -eq $presets.Count - 1) { 0 } else { 4 }), 0)
    $b.Tag = $presets[$i]
    $b.Add_Click({ $script:ChosenMinutes = [int]$this.Tag; $form.Close() })
    $presetRow.Controls.Add($b, $i, 0)
}
$presetRow.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100))) | Out-Null
$st.Controls.Add($presetRow, 0, $r)

# Live preview of the auto-off time
$r = Add-Row $st
$preview = New-Label "" 10 $accent $true 14
$st.Controls.Add($preview, 0, $r)

function Update-Preview {
    param([int]$Minutes)
    $end = (Get-Date).AddMinutes($Minutes)
    $preview.Text = "Auto-off at  $($end.ToString('HH:mm:ss'))    ($Minutes min from now)"
}

$r = Add-Row $st; $st.Controls.Add((New-Label "Custom (1-1440 min)" 9 $muted $false 8), 0, $r)

# Numeric field and its button share one row
$r = Add-Row $st "Abs" $BTN_H
$customRow = New-Object System.Windows.Forms.TableLayoutPanel
$customRow.Dock = "Fill"
$customRow.ColumnCount = 2
$customRow.RowCount = 1
$customRow.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 120))) | Out-Null
$customRow.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100))) | Out-Null
$customRow.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100))) | Out-Null
$customRow.BackColor = $bg
$customRow.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 0)

$num = New-Object System.Windows.Forms.NumericUpDown
$num.Minimum = 1
$num.Maximum = 1440
$num.Value = 45
$num.Dock = "Fill"
$num.Margin = New-Object System.Windows.Forms.Padding(0, 0, 6, 0)
$num.BackColor = $panel
$num.ForeColor = $fg
$customRow.Controls.Add($num, 0, 0)

$btnStartCustom = New-Button "Start custom break" $panel $accent 0
$btnStartCustom.Margin = New-Object System.Windows.Forms.Padding(0)
$btnStartCustom.Add_Click({ $script:ChosenMinutes = [int]$num.Value; $form.Close() })
$customRow.Controls.Add($btnStartCustom, 1, 0)
$st.Controls.Add($customRow, 0, $r)

# Spacer pushes the actions to the bottom edge.
$r = Add-Row $st "Fill"
$r = Add-Row $st "Abs" $BTN_H

# Right-aligned Cancel
$actionRow = New-Object System.Windows.Forms.TableLayoutPanel
$actionRow.Dock = "Fill"
$actionRow.ColumnCount = 2
$actionRow.RowCount = 1
$actionRow.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100))) | Out-Null
$actionRow.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 140))) | Out-Null
$actionRow.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100))) | Out-Null
$actionRow.BackColor = $bg
$actionRow.Margin = New-Object System.Windows.Forms.Padding(0)

$btnCancel = New-Button "Cancel" $panel $line 0
$btnCancel.ForeColor = $muted
$btnCancel.Add_Click({ $script:ChosenMinutes = 0; $form.Close() })
$actionRow.Controls.Add($btnCancel, 1, 0)
$st.Controls.Add($actionRow, 0, $r)

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

$done = New-BaseForm -Title "NightWatch" -Height 240
$dst = New-Stack
$done.Controls.Add($dst) | Out-Null

$r = Add-Row $dst; $dst.Controls.Add((New-Label "STUDY BREAK ACTIVATED" 15 $accent $true 6), 0, $r)
$r = Add-Row $dst; $dst.Controls.Add((New-Label "$minutes minute break - auto-shutdown is PAUSED." 11 $fg $false 6), 0, $r)
$r = Add-Row $dst; $dst.Controls.Add((New-Label "Auto-off at $($expiresAt.ToString('HH:mm:ss'))" 12 $fg $true 6), 0, $r)
$r = Add-Row $dst; $dst.Controls.Add((New-Label "It turns itself off - no need to click again." 9 $muted $false 10), 0, $r)
$r = Add-Row $dst "Fill"
$r = Add-Row $dst "Abs" $BTN_H

# Right-aligned acknowledgement button
$okRow = New-Object System.Windows.Forms.TableLayoutPanel
$okRow.Dock = "Fill"
$okRow.ColumnCount = 2
$okRow.RowCount = 1
$okRow.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100))) | Out-Null
$okRow.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 140))) | Out-Null
$okRow.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100))) | Out-Null
$okRow.BackColor = $bg
$okRow.Margin = New-Object System.Windows.Forms.Padding(0)

$btnOk = New-Button "Got it" $accent $accent 0 $true
$btnOk.Add_Click({ $done.Close() })
$okRow.Controls.Add($btnOk, 1, 0)
$dst.Controls.Add($okRow, 0, $r)

$done.AcceptButton = $btnOk
$done.CancelButton = $btnOk
$done.ShowDialog() | Out-Null
$done.Dispose()
