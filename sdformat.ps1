<#
  sdformat.ps1 - watch for SD cards / removable drives and format them the instant
  they're inserted, announcing via Windows text-to-speech.

      on insert  -> shouts "rishav found you"
      on success -> shouts "rishav pull me out"

  Detection is by DRIVE LETTER: when a new removable/fixed-removable volume appears
  (DriveType 2 or 3) that wasn't present at startup, it's treated as a fresh insert.
  This catches cards no matter how the reader enumerates them.

  WARNING: erases newly inserted drives with NO confirmation.
  Safety rails: ignores everything present at startup (so your C: and existing
  drives are safe), never touches the system drive, skips network/optical drives.

  Run as Administrator or the format will fail.
#>

# ----- config -----
$VolName       = 'SDCARD'      # FAT32 label: <=11 chars
$PollInterval  = 2            # seconds between scans
$Fat32MaxBytes = 32GB         # <=32GB -> FAT32, larger -> exFAT

# ----- tts -----
Add-Type -AssemblyName System.Speech
$script:synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
function Shout($text) { try { $script:synth.Speak($text) } catch {} }
function Log($msg)    { Write-Host ('{0}  {1}' -f (Get-Date -Format 'HH:mm:ss'), $msg) }

# Drive letters worth formatting: 2 = Removable (SD/USB), 3 = Local fixed
# (some built-in readers report cards as "fixed"). Network/optical are excluded.
function Get-CandidateLetters {
  Get-CimInstance Win32_LogicalDisk -Filter 'DriveType = 2 OR DriveType = 3' |
    Select-Object -ExpandProperty DeviceID      # e.g. 'D:'
}

function Format-Letter($id) {                    # $id like 'D:'
  $letter = $id.TrimEnd(':')
  $vol    = Get-Volume -DriveLetter $letter -ErrorAction SilentlyContinue
  $bytes  = if ($vol) { [int64]$vol.Size } else { 0 }
  $fs     = if ($bytes -le $Fat32MaxBytes) { 'FAT32' } else { 'exFAT' }
  Log ("Full-formatting {0} ({1} GB) as {2} (writes every sector - can take a while) ..." `
       -f $id, [math]::Round($bytes/1GB,1), $fs)
  try {
    Format-Volume -DriveLetter $letter -FileSystem $fs -NewFileSystemLabel $VolName `
                  -Full -Force -Confirm:$false -ErrorAction Stop | Out-Null
    Log ("DONE {0} -> {1} ({2})" -f $id, $fs, $VolName)
    Shout 'rishav pull me out'
  } catch {
    Log ("FAIL {0}: {1}" -f $id, $_.Exception.Message)
  }
}

# ----- main -----
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
         ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) { Write-Warning 'Not elevated - formatting will fail. Re-launch PowerShell as Administrator.' }

$sysDrive = $env:SystemDrive   # e.g. 'C:' - never format this

Log 'Watching for SD cards by drive letter. NEW inserts will be ERASED. Ctrl+C to stop.'
$seen = [System.Collections.Generic.HashSet[string]]::new()
foreach ($d in Get-CandidateLetters) { [void]$seen.Add($d) }
$list = if ($seen.Count) { ($seen) -join ', ' } else { 'none' }
Log "Ignoring drives present at startup: $list"

while ($true) {
  $current = @(Get-CandidateLetters)
  foreach ($d in @($seen)) { if ($current -notcontains $d) { [void]$seen.Remove($d) } }  # removal re-arms
  foreach ($d in $current) {
    if ($seen.Contains($d)) { continue }
    [void]$seen.Add($d)
    if ($d -eq $sysDrive) { Log "SKIP $d: system drive"; continue }
    Log "Detected $d"
    Shout 'rishav found you'
    Format-Letter $d
  }
  Start-Sleep -Seconds $PollInterval
}
