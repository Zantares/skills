# Restore globalStorage state.vscdb from a Desktop backup folder.
# Cursor MUST be fully quit.
# Usage: powershell -ExecutionPolicy Bypass -File .\restore-cursor-vscdb-backup.ps1

$ErrorActionPreference = 'Stop'

if (@(Get-Process | Where-Object { $_.ProcessName -like 'Cursor*' }).Count -gt 0) {
  throw 'Quit Cursor completely first.'
}

$dest = Join-Path $env:APPDATA 'Cursor\User\globalStorage\state.vscdb'
$desktop = [Environment]::GetFolderPath('Desktop')
$backups = Get-ChildItem $desktop -Directory -Filter 'cursor_*backup_*' |
  Sort-Object LastWriteTime -Descending

Write-Host 'Available backups on Desktop:'
$i = 0
$map = @{}
foreach ($b in $backups) {
  $i++
  $cands = @()
  $cands += Get-ChildItem $b.FullName -Filter 'state.vscdb' -ErrorAction SilentlyContinue
  $cands += Get-ChildItem $b.FullName -Filter '*.vscdb' -ErrorAction SilentlyContinue
  $pick = $cands | Sort-Object { if ($_.Name -eq 'state.vscdb') { 0 } else { 1 } }, Length -Descending | Select-Object -First 1
  $map[$i] = $pick
  if ($pick) {
    Write-Host ("[{0}] {1}  file={2} size={3:N0} time={4}" -f $i, $b.Name, $pick.Name, $pick.Length, $b.LastWriteTime)
  } else {
    Write-Host ("[{0}] {1}  (no vscdb found)" -f $i, $b.Name)
  }
}

Write-Host ''
Write-Host 'Enter number to restore (or Q to quit):'
$ans = Read-Host
if ($ans -eq 'Q' -or $ans -eq 'q') { exit 0 }
$n = [int]$ans
$src = $map[$n]
if (-not $src) { throw 'Invalid selection' }

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$pre = Join-Path $desktop "cursor_pre_restore_backup_$stamp"
New-Item -ItemType Directory -Force -Path $pre | Out-Null
if (Test-Path $dest) { Copy-Item $dest (Join-Path $pre 'state.vscdb') -Force }
Write-Host "Current DB backed up to $pre"

Copy-Item $src.FullName $dest -Force
Remove-Item ($dest + '-wal'), ($dest + '-shm') -ErrorAction SilentlyContinue
Write-Host "Restored $($src.FullName) -> $dest"
Write-Host 'Cleared wal/shm. Reopen Cursor.'
Read-Host 'Press Enter to continue'
