<#
.SYNOPSIS
    NightWatch Study Break Button (v3.1)
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
$accentDim = [System.Drawing.Color]::FromArgb(60, 96, 150)
$danger    = [System.Drawing.Color]::FromArgb(226, 96, 96)
$line      = [System.Drawing.Color]::FromArgb(58, 62, 74)

function New-Label {
    param($Text, $Size, $Color, $Bold, $X, $Y, $W = 380)
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $Text
    $style = if ($Bold) { [System.Drawing.FontStyle]::Bold } else { [System.Drawing.FontStyle]::Regular }
    $l.Font = New-Object System.Drawing.Font("Segoe UI", $Size, $style)
    $l.ForeColor = $Color
    $l.Location = New-Object System.Drawing.Point($X, $Y)
    $l.Size = New-Object System.Drawing.Size($W, 26)
    return $l
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

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "NightWatch"
    $dlg.ClientSize = New-Object System.Drawing.Size(420, 210)
    $dlg.StartPosition = "CenterScreen"
    $dlg.FormBorderStyle = "FixedDialog"
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false
    $dlg.TopMost = $true
    $dlg.BackColor = $bg
    $dlg.ForeColor = $fg

    $dlg.Controls.Add((New-Label "STUDY BREAK IS ACTIVE" 10 $muted $true 24 22))
    $dlg.Controls.Add((New-Label "Auto-shutdown is paused." 13 $fg $false 24 46))
    $dlg.Controls.Add((New-Label "Ends at  $($expiresAt.ToString('HH:mm:ss'))" 11 $accent $true 24 78))
    $dlg.Controls.Add((New-Label "$durationMinutes min break  |  $remaining min remaining" 10 $muted $false 24 104))

    $btnKeep = New-Object System.Windows.Forms.Button
    $btnKeep.Text = "Keep break"
    $btnKeep.Size = New-Object System.Drawing.Size(170, 40)
    $btnKeep.Location = New-Object System.Drawing.Point(24, 150)
    $btnKeep.FlatStyle = "Flat"
    $btnKeep.FlatAppearance.BorderSize = 1
    $btnKeep.FlatAppearance.BorderColor = $line
    $btnKeep.BackColor = $panel
    $btnKeep.ForeColor = $fg
    $btnKeep.Add_Click({ $script:EndNow = $false; $dlg.Close() })
    $dlg.Controls.Add($btnKeep)

    $btnEnd = New-Object System.Windows.Forms.Button
    $btnEnd.Text = "End break now"
    $btnEnd.Size = New-Object System.Drawing.Size(170, 40)
    $btnEnd.Location = New-Object System.Drawing.Point(226, 150)
    $btnEnd.FlatStyle = "Flat"
    $btnEnd.FlatAppearance.BorderSize = 0
    $btnEnd.BackColor = $danger
    $btnEnd.ForeColor = $fg
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
$form = New-Object System.Windows.Forms.Form
$form.Text = "NightWatch - Study Break"
$form.ClientSize = New-Object System.Drawing.Size(420, 300)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.MinimizeBox = $false
$form.TopMost = $true
$form.BackColor = $bg
$form.ForeColor = $fg

$form.Controls.Add((New-Label "How long is your study break?" 15 $fg $true 24 20))
$form.Controls.Add((New-Label "Auto-shutdown is paused for this long, then re-arms by itself." 9 $muted $false 24 50))

$script:ChosenMinutes = 0
$script:Preset = 30

# Live preview label
$preview = New-Label "" 10 $accent $true 24 132
$form.Controls.Add($preview)

function Update-Preview {
    param([int]$Minutes)
    $end = (Get-Date).AddMinutes($Minutes)
    $preview.Text = "Auto-off at  $($end.ToString('HH:mm:ss'))    ($Minutes min from now)"
}

# Preset buttons
$presets = @(15, 30, 40, 60)
$x = 24
foreach ($m in $presets) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = "$m min"
    $b.Tag = $m
    $b.Size = New-Object System.Drawing.Size(84, 42)
    $b.Location = New-Object System.Drawing.Point($x, 78)
    $b.FlatStyle = "Flat"
    $b.FlatAppearance.BorderSize = 1
    $b.FlatAppearance.BorderColor = $accent
    $b.BackColor = $panel
    $b.ForeColor = $fg
    $b.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $b.Add_Click({
        $script:ChosenMinutes = [int]$this.Tag
        Update-Preview -Minutes $script:ChosenMinutes
        $form.Close()
    })
    $form.Controls.Add($b)
    $x += 92
}

$form.Controls.Add((New-Label "Custom (1-1440 min)" 9 $muted $false 24 168))

$num = New-Object System.Windows.Forms.NumericUpDown
$num.Minimum = 1
$num.Maximum = 1440
$num.Value = 45
$num.Size = New-Object System.Drawing.Size(110, 28)
$num.Location = New-Object System.Drawing.Point(24, 192)
$num.BackColor = $panel
$num.ForeColor = $fg
$form.Controls.Add($num)

$btnStartCustom = New-Object System.Windows.Forms.Button
$btnStartCustom.Text = "Start custom break"
$btnStartCustom.Size = New-Object System.Drawing.Size(170, 30)
$btnStartCustom.Location = New-Object System.Drawing.Point(150, 191)
$btnStartCustom.FlatStyle = "Flat"
$btnStartCustom.FlatAppearance.BorderSize = 1
$btnStartCustom.FlatAppearance.BorderColor = $accent
$btnStartCustom.BackColor = $panel
$btnStartCustom.ForeColor = $fg
$btnStartCustom.Add_Click({
    $script:ChosenMinutes = [int]$num.Value
    $form.Close()
})
$form.Controls.Add($btnStartCustom)

$btnCancel = New-Object System.Windows.Forms.Button
$btnCancel.Text = "Cancel"
$btnCancel.Size = New-Object System.Drawing.Size(120, 34)
$btnCancel.Location = New-Object System.Drawing.Point(276, 244)
$btnCancel.FlatStyle = "Flat"
$btnCancel.FlatAppearance.BorderSize = 1
$btnCancel.FlatAppearance.BorderColor = $line
$btnCancel.BackColor = $panel
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

$done = New-Object System.Windows.Forms.Form
$done.Text = "NightWatch"
$done.ClientSize = New-Object System.Drawing.Size(420, 180)
$done.StartPosition = "CenterScreen"
$done.FormBorderStyle = "FixedDialog"
$done.MaximizeBox = $false
$done.MinimizeBox = $false
$done.TopMost = $true
$done.BackColor = $bg
$done.ForeColor = $fg
$done.Controls.Add((New-Label "STUDY BREAK ACTIVATED" 15 $accent $true 24 24))
$done.Controls.Add((New-Label "$minutes minute break - auto-shutdown is PAUSED." 11 $fg $false 24 62))
$done.Controls.Add((New-Label "Auto-off at $($expiresAt.ToString('HH:mm:ss'))" 12 $fg $true 24 90))
$done.Controls.Add((New-Label "It turns itself off - no need to click again." 9 $muted $false 24 120))
$btnOk = New-Object System.Windows.Forms.Button
$btnOk.Text = "Got it"
$btnOk.Size = New-Object System.Drawing.Size(120, 34)
$btnOk.Location = New-Object System.Drawing.Point(276, 134)
$btnOk.FlatStyle = "Flat"
$btnOk.FlatAppearance.BorderSize = 0
$btnOk.BackColor = $accent
$btnOk.ForeColor = $fg
$btnOk.Add_Click({ $done.Close() })
$done.Controls.Add($btnOk)
$done.AcceptButton = $btnOk
$done.CancelButton = $btnOk
$done.ShowDialog() | Out-Null
$done.Dispose()
