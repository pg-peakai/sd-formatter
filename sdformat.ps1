<#
  sdformat.ps1 - watch for SD cards and format them the instant they're inserted,
  announcing via Windows text-to-speech.

      on insert  -> shouts "rishav found you"
      on success -> shouts "rishav pull me out"

  WARNING: erases inserted removable disks with NO confirmation.
  Safety rails: skips boot/system disks; only USB/SD/MMC bus disks; and any disk
  already connected when the script starts is ignored (only NEW inserts get wiped).

  Run in an ELEVATED PowerShell (Administrator) or the format will fail.
#>

# ----- config -----
$VolName       = 'SDCARD'              # FAT32 label: <=11 chars
$PollInterval  = 2                     # seconds between scans
$Fat32MaxBytes = 32GB                  # <=32GB -> FAT32, larger -> exFAT
$StrictSD      = $false               # $true = only BusType 'SD' (built-in SD slots)
$Buses         = @('USB','SD','MMC')   # buses treated as removable card media

# ----- tts -----
Add-Type -AssemblyName System.Speech
$script:synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
function Shout($text) { $script:synth.Speak($text) }   # synchronous: announces before acting

function Log($msg) { Write-Host ('{0}  {1}' -f (Get-Date -Format 'HH:mm:ss'), $msg) }

function Get-TargetDisks {
  Get-Disk |
    Where-Object { $_.BusType -in $Buses -and -not $_.IsBoot -and -not $_.IsSystem } |
    Select-Object -ExpandProperty Number
}

# Re-check the disk right before wiping; refuse boot/system, honor strict mode.
function Test-SafeTarget($num) {
  $d = Get-Disk -Number $num -ErrorAction SilentlyContinue
  if (-not $d)                              { Log "SKIP disk $num: gone";              return $false }
  if ($d.IsBoot -or $d.IsSystem)           { Log "SKIP disk $num: boot/system disk";  return $false }
  if ($StrictSD -and $d.BusType -ne 'SD')  { Log "SKIP disk $num: not SD bus (strict)"; return $false }
  if ($d.BusType -notin $Buses)            { Log "SKIP disk $num: bus $($d.BusType)";  return $false }
  return $true
}

function Format-Card($num) {
  $d     = Get-Disk -Number $num
  $bytes = $d.Size
  $fs    = if ($bytes -le $Fat32MaxBytes) { 'FAT32' } else { 'exFAT' }
  Log ("Formatting disk {0} ({1} GB) as {2} ..." -f $num, [math]::Round($bytes/1GB,1), $fs)
  try {
    Clear-Disk    -Number $num -RemoveData -RemoveOEM -Confirm:$false -ErrorAction Stop
    Initialize-Disk -Number $num -PartitionStyle MBR -ErrorAction SilentlyContinue
    $part = New-Partition -DiskNumber $num -UseMaximumSize -AssignDriveLetter -ErrorAction Stop
    Format-Volume -Partition $part -FileSystem $fs -NewFileSystemLabel $VolName `
                  -Force -Confirm:$false -ErrorAction Stop | Out-Null
    Log ("DONE disk {0} -> {1} ({2}) at {3}:" -f $num, $fs, $VolName, $part.DriveLetter)
    Shout 'rishav pull me out'
  } catch {
    Log "FAIL disk $num: $($_.Exception.Message)"
  }
}

# ----- main -----
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
         ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) { Write-Warning 'Not elevated - formatting will fail. Re-launch PowerShell as Administrator.' }

Log 'Watching for SD cards. NEW removable disks will be ERASED on insert. Ctrl+C to stop.'
$seen = [System.Collections.Generic.HashSet[int]]::new()
foreach ($n in Get-TargetDisks) { [void]$seen.Add($n) }   # ignore pre-connected drives
Log ("Ignoring already-connected disks: {0}" -f (($seen) -join ', '))

while ($true) {
  $current = @(Get-TargetDisks)
  foreach ($n in @($seen)) { if ($current -notcontains $n) { [void]$seen.Remove($n) } }  # re-insert re-triggers
  foreach ($n in $current) {
    if ($seen.Contains($n)) { continue }
    [void]$seen.Add($n)
    Log "Detected disk $n"
    Shout 'rishav found you'
    if (Test-SafeTarget $n) { Format-Card $n }
  }
  Start-Sleep -Seconds $PollInterval
}
