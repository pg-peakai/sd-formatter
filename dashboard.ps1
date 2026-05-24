<#
  dashboard.ps1 - GUI dashboard for the SD card auto-formatter.

  A live window with a status banner, a running count, and a scrolling log.
  Quick-formats each newly inserted removable drive (FAT32 <=32GB, else exFAT)
  and announces via TTS ("rishav found you" / "rishav pull me out").

  Ignores drives present at startup; never touches the system drive.
  Run as Administrator. Close the window to stop.
#>

$VolName       = 'SDCARD'
$PollInterval  = 2
$Fat32MaxBytes = 32GB

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Speech

$synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
function Shout($t) { try { $synth.SpeakAsync($t) | Out-Null } catch {} }

# ----- palette -----
$dark  = [System.Drawing.Color]::FromArgb(24,24,32)
$panel = [System.Drawing.Color]::FromArgb(34,34,46)
$green = [System.Drawing.Color]::FromArgb(120,230,150)
$gold  = [System.Drawing.Color]::FromArgb(245,200,80)
$red   = [System.Drawing.Color]::FromArgb(240,110,100)
$grey  = [System.Drawing.Color]::FromArgb(170,170,185)

# ----- window -----
$form = New-Object System.Windows.Forms.Form
$form.Text = 'SD Card Auto-Formatter'
$form.ClientSize = New-Object System.Drawing.Size(640, 470)
$form.StartPosition = 'CenterScreen'
$form.BackColor = $dark
$form.Font = New-Object System.Drawing.Font('Segoe UI', 10)

$status = New-Object System.Windows.Forms.Label
$status.SetBounds(0, 0, 640, 70)
$status.Anchor = 'Top,Left,Right'
$status.TextAlign = 'MiddleCenter'
$status.Font = New-Object System.Drawing.Font('Segoe UI', 17, [System.Drawing.FontStyle]::Bold)
$status.BackColor = $panel
$status.ForeColor = $green
$status.Text = 'WATCHING  -  insert a card'
$form.Controls.Add($status)

$stats = New-Object System.Windows.Forms.Label
$stats.SetBounds(12, 82, 616, 26)
$stats.Anchor = 'Top,Left,Right'
$stats.ForeColor = $grey
$stats.Text = 'Cards formatted: 0'
$form.Controls.Add($stats)

$log = New-Object System.Windows.Forms.ListBox
$log.SetBounds(12, 114, 616, 312)
$log.Anchor = 'Top,Bottom,Left,Right'
$log.BackColor = [System.Drawing.Color]::FromArgb(16,16,22)
$log.ForeColor = $green
$log.BorderStyle = 'FixedSingle'
$log.Font = New-Object System.Drawing.Font('Consolas', 10)
$form.Controls.Add($log)

$hint = New-Object System.Windows.Forms.Label
$hint.SetBounds(12, 432, 616, 26)
$hint.Anchor = 'Bottom,Left,Right'
$hint.ForeColor = $grey
$hint.Text = 'Insert a card to format it. Close this window to stop.'
$form.Controls.Add($hint)

# ----- state -----
$script:seen  = [System.Collections.Generic.HashSet[string]]::new()
$script:count = 0
$sysDrive = $env:SystemDrive

function Add-Log($msg) {
  $log.Items.Insert(0, ('{0}  {1}' -f (Get-Date -Format 'HH:mm:ss'), $msg))
  while ($log.Items.Count -gt 300) { $log.Items.RemoveAt(300) }
}

function Get-CandidateLetters {
  Get-CimInstance Win32_LogicalDisk -Filter 'DriveType = 2 OR DriveType = 3' |
    Select-Object -ExpandProperty DeviceID
}

function Format-Card($id) {
  $letter = $id.TrimEnd(':')
  $vol    = Get-Volume -DriveLetter $letter -ErrorAction SilentlyContinue
  $bytes  = if ($vol) { [int64]$vol.Size } else { 0 }
  $fs     = if ($bytes -le $Fat32MaxBytes) { 'FAT32' } else { 'exFAT' }
  $status.ForeColor = $gold
  $status.Text = "FORMATTING $id ..."
  $status.Refresh()
  Add-Log ("Formatting {0} ({1} GB) as {2}" -f $id, [math]::Round($bytes/1GB,1), $fs)
  try {
    Format-Volume -DriveLetter $letter -FileSystem $fs -NewFileSystemLabel $VolName -Force -Confirm:$false -ErrorAction Stop | Out-Null
    $script:count++
    Add-Log ("DONE {0} -> {1} ({2})" -f $id, $fs, $VolName)
    Shout 'rishav pull me out'
    $status.ForeColor = $green
    $status.Text = "DONE $id  -  insert next card"
  } catch {
    Add-Log ("FAIL {0}: {1}" -f $id, $_.Exception.Message)
    $status.ForeColor = $red
    $status.Text = "FAILED $id"
  }
  $stats.Text = "Cards formatted: $($script:count)    |    Last: $id ($fs)"
}

# ----- poll loop via UI timer (keeps the window responsive) -----
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = $PollInterval * 1000
$timer.Add_Tick({
  $current = @(Get-CandidateLetters)
  foreach ($d in @($script:seen)) { if ($current -notcontains $d) { [void]$script:seen.Remove($d) } }
  foreach ($d in $current) {
    if ($script:seen.Contains($d)) { continue }
    [void]$script:seen.Add($d)
    if ($d -eq $sysDrive) { continue }
    $status.ForeColor = $gold
    $status.Text = "DETECTED $d"
    Add-Log "Detected $d"
    Shout 'rishav found you'
    Format-Card $d
  }
})

# ----- startup -----
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
         ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) {
  $status.ForeColor = $red
  $status.Text = 'NOT ADMIN - formatting will fail'
  Add-Log 'WARNING: not elevated. Close this and re-open PowerShell as Administrator.'
}

foreach ($d in Get-CandidateLetters) { [void]$script:seen.Add($d) }
$seedList = if ($script:seen.Count) { ($script:seen) -join ', ' } else { 'none' }
Add-Log "Watching. Ignoring drives present at startup: $seedList"

$timer.Start()
$form.Add_FormClosing({ $timer.Stop() })
[System.Windows.Forms.Application]::Run($form)
