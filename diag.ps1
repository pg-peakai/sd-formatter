# diag.ps1 - READ ONLY. Formats nothing. Dumps how disks/volumes appear so we can
# fix SD card detection. Run this WITH the SD card inserted, then paste the output.

Write-Host "===== Get-Disk =====" -ForegroundColor Cyan
Get-Disk | Format-Table Number, FriendlyName, BusType, OperationalStatus,
  @{n='SizeGB';e={[math]::Round($_.Size/1GB,1)}}, IsBoot, IsSystem -AutoSize | Out-Host

Write-Host "===== Get-Volume =====" -ForegroundColor Cyan
Get-Volume | Format-Table DriveLetter, FileSystemLabel, FileSystem, DriveType,
  @{n='SizeGB';e={[math]::Round($_.Size/1GB,1)}} -AutoSize | Out-Host

Write-Host "===== Win32_DiskDrive (WMI) =====" -ForegroundColor Cyan
Get-CimInstance Win32_DiskDrive | Format-Table Index, Model, InterfaceType, MediaType,
  @{n='SizeGB';e={[math]::Round($_.Size/1GB,1)}} -AutoSize | Out-Host

Write-Host "===== Win32_LogicalDisk (removable = DriveType 2) =====" -ForegroundColor Cyan
Get-CimInstance Win32_LogicalDisk | Format-Table DeviceID, DriveType, VolumeName,
  @{n='SizeGB';e={[math]::Round($_.Size/1GB,1)}} -AutoSize | Out-Host
