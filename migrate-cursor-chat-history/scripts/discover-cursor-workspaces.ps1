# READ-ONLY: list Cursor workspaceStorage ids, URIs, db sizes
# Usage: powershell -ExecutionPolicy Bypass -File .\discover-cursor-workspaces.ps1
# Optional: -PathFilter 'teng.lu' or 'luteng'

param(
  [string]$PathFilter = ''
)

$ErrorActionPreference = 'Continue'
$wsRoot = Join-Path $env:APPDATA 'Cursor\User\workspaceStorage'
$globalDb = Join-Path $env:APPDATA 'Cursor\User\globalStorage\state.vscdb'
$storageJson = Join-Path $env:APPDATA 'Cursor\User\globalStorage\storage.json'

Write-Host "workspaceStorage=$wsRoot"
Write-Host "globalDb=$globalDb exists=$(Test-Path $globalDb)"
if (Test-Path $globalDb) {
  $gi = Get-Item $globalDb
  Write-Host ("  size={0:N0} mtime={1}" -f $gi.Length, $gi.LastWriteTime)
}

Write-Host ''
Write-Host '=== workspaces ==='
Get-ChildItem $wsRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
  $wj = Join-Path $_.FullName 'workspace.json'
  $db = Join-Path $_.FullName 'state.vscdb'
  if (-not (Test-Path $wj)) { return }
  $json = (Get-Content $wj -Raw).Trim()
  if ($PathFilter -and ($json -notlike "*$PathFilter*")) { return }
  $dbSize = if (Test-Path $db) { (Get-Item $db).Length } else { 0 }
  $mtime = if (Test-Path $db) { (Get-Item $db).LastWriteTime } else { $_.LastWriteTime }
  Write-Host ("id={0}  db={1:N0}  mtime={2}" -f $_.Name, $dbSize, $mtime)
  Write-Host ("  {0}" -f $json)
}

if (Test-Path $storageJson) {
  Write-Host ''
  Write-Host '=== storage.json profileAssociations.workspaces (subset) ==='
  try {
    $sj = Get-Content $storageJson -Raw | ConvertFrom-Json
    $sj.profileAssociations.workspaces.PSObject.Properties | ForEach-Object {
      if (-not $PathFilter -or $_.Name -like "*$PathFilter*") {
        Write-Host ("  {0} => {1}" -f $_.Name, $_.Value)
      }
    }
  } catch {
    Write-Host "  (parse failed: $_)"
  }
}

Write-Host ''
Write-Host 'Pair OLD/NEW by same ssh-remote host + old/new path, then run diagnose/fix scripts with those ids.'
Read-Host 'Press Enter to continue'
