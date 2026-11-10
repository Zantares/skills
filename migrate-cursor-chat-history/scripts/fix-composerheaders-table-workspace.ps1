# =============================================================================
# ROOT CAUSE FIX: Cursor History/@ reads SQLite table `composerHeaders`
# (composer.composerHeaders.tableGateEnabled=true, migratedToTable=1).
# Previous scripts only rewrote ItemTable JSON key composer.composerHeaders,
# which the UI no longer uses as the primary index.
#
# This script ONLY:
#   UPDATE composerHeaders SET workspaceId = NEW
#   WHERE workspaceId = OLD
# Optionally patches value JSON workspaceIdentifier if present.
# Does NOT mass-replace cursorDiskKV / bubble bodies.
#
# Pair:
#   OLD: fcb79932691a7c545711254f250a7d1e  (mlc09 /home/luteng)
#   NEW: 5922db438f27b34d5a63fe374333a8f5  (mlc09 /home/teng.lu)
#
# Usage (Cursor FULLY quit):
#   powershell -ExecutionPolicy Bypass -File .\fix-composerheaders-table-workspace.ps1 -OldId <OLD> -NewId <NEW>
# =============================================================================

param(
  [Parameter(Mandatory=$true)][string]$OldId,
  [Parameter(Mandatory=$true)][string]$NewId,
  [string]$NewPath = '/home/teng.lu',
  [string]$OldPath = '/home/luteng',
  [string]$EncodedAuthority = 'ssh-remote%2B7b22686f73744e616d65223a226d6c633039227d',
  [string[]]$GoldIds = @()
)

$ErrorActionPreference = 'Stop'

$sqliteCode = @'
using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Collections.Generic;

public static class WinSqlite3Fix {
  public const int SQLITE_OK = 0;
  public const int SQLITE_ROW = 100;
  public const int SQLITE_DONE = 101;
  public const int SQLITE_OPEN_READWRITE = 2;
  public const int SQLITE_OPEN_READONLY = 1;
  private static readonly IntPtr SQLITE_TRANSIENT = new IntPtr(-1);

  [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
  public static extern int sqlite3_open_v2(byte[] filename, out IntPtr db, int flags, IntPtr zVfs);
  [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
  public static extern int sqlite3_close(IntPtr db);
  [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
  public static extern int sqlite3_exec(IntPtr db, byte[] sql, IntPtr callback, IntPtr arg, out IntPtr errMsg);
  [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
  public static extern int sqlite3_prepare_v2(IntPtr db, byte[] sql, int nByte, out IntPtr stmt, IntPtr pzTail);
  [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
  public static extern int sqlite3_step(IntPtr stmt);
  [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
  public static extern int sqlite3_finalize(IntPtr stmt);
  [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
  public static extern int sqlite3_bind_text(IntPtr stmt, int i, byte[] val, int n, IntPtr destructor);
  [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
  public static extern int sqlite3_bind_int64(IntPtr stmt, int i, long val);
  [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
  public static extern IntPtr sqlite3_column_text(IntPtr stmt, int iCol);
  [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
  public static extern int sqlite3_column_bytes(IntPtr stmt, int iCol);
  [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
  public static extern IntPtr sqlite3_column_blob(IntPtr stmt, int iCol);
  [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
  public static extern int sqlite3_column_type(IntPtr stmt, int iCol);
  [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
  public static extern long sqlite3_column_int64(IntPtr stmt, int iCol);
  [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
  public static extern int sqlite3_changes(IntPtr db);
  [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
  public static extern IntPtr sqlite3_errmsg(IntPtr db);

  public static byte[] Z(string s) { return Encoding.UTF8.GetBytes(s + "\0"); }
  public static string PtrToUtf8(IntPtr p) {
    if (p == IntPtr.Zero) return null;
    int len = 0; while (Marshal.ReadByte(p, len) != 0) len++;
    byte[] buf = new byte[len]; Marshal.Copy(p, buf, 0, len);
    return Encoding.UTF8.GetString(buf);
  }
  public static IntPtr Open(string path, bool readOnly) {
    IntPtr db; int flags = readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE;
    int rc = sqlite3_open_v2(Z(path), out db, flags, IntPtr.Zero);
    if (rc != SQLITE_OK) throw new Exception("open failed " + path + " rc=" + rc);
    return db;
  }
  public static void Exec(IntPtr db, string sql) {
    IntPtr err; int rc = sqlite3_exec(db, Z(sql), IntPtr.Zero, IntPtr.Zero, out err);
    if (rc != SQLITE_OK) throw new Exception("exec " + rc + ": " + PtrToUtf8(err));
  }
  public static string GetText(IntPtr db, string table, string key) {
    IntPtr stmt; int rc = sqlite3_prepare_v2(db, Z("SELECT value FROM " + table + " WHERE key=?"), -1, out stmt, IntPtr.Zero);
    if (rc != SQLITE_OK) throw new Exception(PtrToUtf8(sqlite3_errmsg(db)));
    try {
      byte[] k = Encoding.UTF8.GetBytes(key);
      sqlite3_bind_text(stmt, 1, k, k.Length, SQLITE_TRANSIENT);
      if (sqlite3_step(stmt) != SQLITE_ROW) return null;
      int t = sqlite3_column_type(stmt, 0);
      if (t == 3) return PtrToUtf8(sqlite3_column_text(stmt, 0));
      if (t == 4) {
        int n = sqlite3_column_bytes(stmt, 0); byte[] buf = new byte[n];
        IntPtr p = sqlite3_column_blob(stmt, 0);
        if (n > 0 && p != IntPtr.Zero) Marshal.Copy(p, buf, 0, n);
        return Encoding.UTF8.GetString(buf);
      }
      return null;
    } finally { sqlite3_finalize(stmt); }
  }
  public static long CountWhere(IntPtr db, string sql, string a, string b) {
    IntPtr stmt; int rc = sqlite3_prepare_v2(db, Z(sql), -1, out stmt, IntPtr.Zero);
    if (rc != SQLITE_OK) throw new Exception(PtrToUtf8(sqlite3_errmsg(db)));
    try {
      if (a != null) {
        byte[] ba = Encoding.UTF8.GetBytes(a);
        sqlite3_bind_text(stmt, 1, ba, ba.Length, SQLITE_TRANSIENT);
      }
      if (b != null) {
        byte[] bb = Encoding.UTF8.GetBytes(b);
        sqlite3_bind_text(stmt, 2, bb, bb.Length, SQLITE_TRANSIENT);
      }
      if (sqlite3_step(stmt) != SQLITE_ROW) return -1;
      return sqlite3_column_int64(stmt, 0);
    } finally { sqlite3_finalize(stmt); }
  }
  public static bool HasComposer(IntPtr db, string composerId) {
    IntPtr stmt; int rc = sqlite3_prepare_v2(db, Z("SELECT workspaceId FROM composerHeaders WHERE composerId=?"), -1, out stmt, IntPtr.Zero);
    if (rc != SQLITE_OK) throw new Exception(PtrToUtf8(sqlite3_errmsg(db)));
    try {
      byte[] k = Encoding.UTF8.GetBytes(composerId);
      sqlite3_bind_text(stmt, 1, k, k.Length, SQLITE_TRANSIENT);
      if (sqlite3_step(stmt) != SQLITE_ROW) return false;
      return true;
    } finally { sqlite3_finalize(stmt); }
  }
  public static string GetWorkspaceOf(IntPtr db, string composerId) {
    IntPtr stmt; int rc = sqlite3_prepare_v2(db, Z("SELECT workspaceId FROM composerHeaders WHERE composerId=?"), -1, out stmt, IntPtr.Zero);
    if (rc != SQLITE_OK) throw new Exception(PtrToUtf8(sqlite3_errmsg(db)));
    try {
      byte[] k = Encoding.UTF8.GetBytes(composerId);
      sqlite3_bind_text(stmt, 1, k, k.Length, SQLITE_TRANSIENT);
      if (sqlite3_step(stmt) != SQLITE_ROW) return null;
      return PtrToUtf8(sqlite3_column_text(stmt, 0));
    } finally { sqlite3_finalize(stmt); }
  }
  public static List<string> SampleRows(IntPtr db, string workspaceId, int limit) {
    var list = new List<string>();
    IntPtr stmt; int rc = sqlite3_prepare_v2(db, Z("SELECT composerId, isArchived, substr(value,1,160) FROM composerHeaders WHERE workspaceId=? ORDER BY recency DESC LIMIT ?"), -1, out stmt, IntPtr.Zero);
    if (rc != SQLITE_OK) throw new Exception(PtrToUtf8(sqlite3_errmsg(db)));
    try {
      byte[] k = Encoding.UTF8.GetBytes(workspaceId);
      sqlite3_bind_text(stmt, 1, k, k.Length, SQLITE_TRANSIENT);
      sqlite3_bind_int64(stmt, 2, limit);
      while (sqlite3_step(stmt) == SQLITE_ROW) {
        string id = PtrToUtf8(sqlite3_column_text(stmt, 0));
        long arch = sqlite3_column_int64(stmt, 1);
        string v = PtrToUtf8(sqlite3_column_text(stmt, 2));
        list.Add(id + " archived=" + arch + " value~" + v);
      }
    } finally { sqlite3_finalize(stmt); }
    return list;
  }
  public static int UpdateWorkspace(IntPtr db, string oldId, string newId) {
    IntPtr stmt; int rc = sqlite3_prepare_v2(db, Z("UPDATE composerHeaders SET workspaceId=? WHERE workspaceId=?"), -1, out stmt, IntPtr.Zero);
    if (rc != SQLITE_OK) throw new Exception(PtrToUtf8(sqlite3_errmsg(db)));
    try {
      byte[] n = Encoding.UTF8.GetBytes(newId);
      byte[] o = Encoding.UTF8.GetBytes(oldId);
      sqlite3_bind_text(stmt, 1, n, n.Length, SQLITE_TRANSIENT);
      sqlite3_bind_text(stmt, 2, o, o.Length, SQLITE_TRANSIENT);
      rc = sqlite3_step(stmt);
      if (rc != SQLITE_DONE) throw new Exception(PtrToUtf8(sqlite3_errmsg(db)));
      return sqlite3_changes(db);
    } finally { sqlite3_finalize(stmt); }
  }
  public class HeaderRow {
    public string composerId;
    public string value;
  }
  public static List<HeaderRow> LoadValuesForWorkspace(IntPtr db, string workspaceId) {
    var list = new List<HeaderRow>();
    IntPtr stmt; int rc = sqlite3_prepare_v2(db, Z("SELECT composerId, value FROM composerHeaders WHERE workspaceId=?"), -1, out stmt, IntPtr.Zero);
    if (rc != SQLITE_OK) throw new Exception(PtrToUtf8(sqlite3_errmsg(db)));
    try {
      byte[] k = Encoding.UTF8.GetBytes(workspaceId);
      sqlite3_bind_text(stmt, 1, k, k.Length, SQLITE_TRANSIENT);
      while (sqlite3_step(stmt) == SQLITE_ROW) {
        var row = new HeaderRow();
        row.composerId = PtrToUtf8(sqlite3_column_text(stmt, 0));
        int t = sqlite3_column_type(stmt, 1);
        if (t == 3) row.value = PtrToUtf8(sqlite3_column_text(stmt, 1));
        else if (t == 4) {
          int n = sqlite3_column_bytes(stmt, 1); byte[] buf = new byte[n];
          IntPtr p = sqlite3_column_blob(stmt, 1);
          if (n > 0 && p != IntPtr.Zero) Marshal.Copy(p, buf, 0, n);
          row.value = Encoding.UTF8.GetString(buf);
        }
        list.Add(row);
      }
    } finally { sqlite3_finalize(stmt); }
    return list;
  }
  public static void UpdateValue(IntPtr db, string composerId, string value) {
    IntPtr stmt; int rc = sqlite3_prepare_v2(db, Z("UPDATE composerHeaders SET value=? WHERE composerId=?"), -1, out stmt, IntPtr.Zero);
    if (rc != SQLITE_OK) throw new Exception(PtrToUtf8(sqlite3_errmsg(db)));
    try {
      byte[] v = Encoding.UTF8.GetBytes(value ?? "");
      byte[] k = Encoding.UTF8.GetBytes(composerId);
      sqlite3_bind_text(stmt, 1, v, v.Length, SQLITE_TRANSIENT);
      sqlite3_bind_text(stmt, 2, k, k.Length, SQLITE_TRANSIENT);
      rc = sqlite3_step(stmt);
      if (rc != SQLITE_DONE) throw new Exception(PtrToUtf8(sqlite3_errmsg(db)));
    } finally { sqlite3_finalize(stmt); }
  }
}
'@

Add-Type -TypeDefinition $sqliteCode -Language CSharp -ErrorAction Stop

function Out([string]$s) { Write-Host $s }

$GlobalDb = Join-Path $env:APPDATA 'Cursor\User\globalStorage\state.vscdb'
$Stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$BackupDir = Join-Path $env:USERPROFILE "Desktop\cursor_composerHeaders_table_backup_$Stamp"

Out '==== FIX composerHeaders TABLE workspaceId ===='
Out ("globalDb=$GlobalDb")
Out ("OLD workspaceId=$OldId")
Out ("NEW workspaceId=$NewId")

$procs = @(Get-Process | Where-Object { $_.ProcessName -like 'Cursor*' })
if ($procs.Count -gt 0) {
  Out ("ERROR: Cursor still running ($($procs.Count) processes). Fully quit Cursor first.")
  Read-Host 'Press Enter to continue'
  exit 1
}
if (-not (Test-Path $GlobalDb)) { throw "Missing $GlobalDb" }

# preview read-only
$db = [WinSqlite3Fix]::Open($GlobalDb, $true)
try {
  $gate = [WinSqlite3Fix]::GetText($db, 'ItemTable', 'composer.composerHeaders.tableGateEnabled')
  $mig = [WinSqlite3Fix]::GetText($db, 'cursorDiskKV', 'composer.composerHeaders.migratedToTable')
  if (-not $mig) { $mig = [WinSqlite3Fix]::GetText($db, 'ItemTable', 'composer.composerHeaders.migratedToTable') }
  Out ("tableGateEnabled=$gate migratedToTable=$mig")

  $nOld = [WinSqlite3Fix]::CountWhere($db, 'SELECT COUNT(*) FROM composerHeaders WHERE workspaceId=?', $OldId, $null)
  $nNew = [WinSqlite3Fix]::CountWhere($db, 'SELECT COUNT(*) FROM composerHeaders WHERE workspaceId=?', $NewId, $null)
  $nAll = [WinSqlite3Fix]::CountWhere($db, 'SELECT COUNT(*) FROM composerHeaders', $null, $null)
  $nOldActive = [WinSqlite3Fix]::CountWhere($db, 'SELECT COUNT(*) FROM composerHeaders WHERE workspaceId=? AND isArchived=0', $OldId, $null)
  Out ("composerHeaders total=$nAll")
  Out ("  workspaceId=OLD: $nOld (active/non-archived=$nOldActive)")
  Out ("  workspaceId=NEW: $nNew")

  foreach ($gid in $GoldIds) {
    $ws = [WinSqlite3Fix]::GetWorkspaceOf($db, $gid)
    if ($null -eq $ws) { Out ("  gold $gid : NOT in composerHeaders table") }
    else { Out ("  gold $gid : workspaceId=$ws") }
  }

  Out 'Sample OLD rows (by recency):'
  foreach ($s in [WinSqlite3Fix]::SampleRows($db, $OldId, 8)) { Out "  $s" }
  Out 'Sample NEW rows (by recency):'
  foreach ($s in [WinSqlite3Fix]::SampleRows($db, $NewId, 8)) { Out "  $s" }
}
finally {
  [void][WinSqlite3Fix]::sqlite3_close($db)
}

if ($nOld -le 0) {
  Out 'Nothing to migrate (no OLD workspaceId rows). Abort.'
  Read-Host 'Press Enter to continue'
  exit 0
}

Out ''
Out 'This will:'
Out "  1) Backup state.vscdb (+ wal/shm if any) to Desktop"
Out "  2) UPDATE composerHeaders SET workspaceId=NEW WHERE workspaceId=OLD  ($nOld rows)"
Out '  3) If value JSON contains workspaceIdentifier with OLD id/path, patch those fields to NEW'
Out '  4) Clear wal/shm after write'
Out 'It will NOT touch bubble bodies / mass string replace.'
Write-Host 'Continue? [Y/N]' -ForegroundColor Yellow
$ans = Read-Host
if ($ans -notin @('Y','y')) { Out 'Aborted.'; exit 0 }

New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Copy-Item $GlobalDb (Join-Path $BackupDir 'state.vscdb') -Force
foreach ($sfx in @('-wal','-shm')) {
  $p = $GlobalDb + $sfx
  if (Test-Path $p) { Copy-Item $p (Join-Path $BackupDir ("state.vscdb$sfx")) -Force }
}
Out ("Backup -> $BackupDir")

$db = [WinSqlite3Fix]::Open($GlobalDb, $false)
try {
  [WinSqlite3Fix]::Exec($db, 'BEGIN IMMEDIATE')
  $changed = [WinSqlite3Fix]::UpdateWorkspace($db, $OldId, $NewId)
  Out ("Updated workspaceId rows: $changed")

  # Patch value JSON workspaceIdentifier if present (now all under NEW)
  $rows = [WinSqlite3Fix]::LoadValuesForWorkspace($db, $NewId)
  $patched = 0
  $newUri = "vscode-remote://$EncodedAuthority$NewPath"
  $newAuth = $EncodedAuthority
  foreach ($row in $rows) {
    if ([string]::IsNullOrEmpty($row.value)) { continue }
    if ($row.value -notmatch 'workspaceIdentifier' -and $row.value -notlike "*$OldId*" -and $row.value -notlike "*$OldPath*") {
      continue
    }
    try { $obj = $row.value | ConvertFrom-Json } catch { continue }
    $dirty = $false
    if ($obj.workspaceIdentifier) {
      $ws = $obj.workspaceIdentifier
      if ([string]$ws.id -eq $OldId -or [string]$ws.id -ne $NewId) {
        $ws.id = $NewId
        $dirty = $true
      }
      if ($ws.uri) {
        if ([string]$ws.uri.path -eq $OldPath -or [string]$ws.uri.path -ne $NewPath) {
          $ws.uri.path = $NewPath
          $dirty = $true
        }
        if ($ws.uri.PSObject.Properties['fsPath']) {
          $ws.uri.fsPath = ('\' + ($NewPath.TrimStart('/') -replace '/','\'))
          $dirty = $true
        }
        if ($ws.uri.PSObject.Properties['external']) {
          $ws.uri.external = $newUri
          $dirty = $true
        }
        if ($ws.uri.PSObject.Properties['authority']) {
          $ws.uri.authority = $newAuth
          $dirty = $true
        }
      }
      $obj.workspaceIdentifier = $ws
    }
    # also raw replace of old id in value if still present as workspaceId field
    $json = $obj | ConvertTo-Json -Depth 20 -Compress
    if ($json.Contains($OldId) -or $json.Contains($OldPath)) {
      $oldFs = '\' + ($OldPath.TrimStart('/') -replace '/','\')
      $newFs = '\' + ($NewPath.TrimStart('/') -replace '/','\')
      $json = $json.Replace($OldId, $NewId).Replace($OldPath, $NewPath).Replace($oldFs, $newFs)
      $dirty = $true
    }
    if ($dirty) {
      [WinSqlite3Fix]::UpdateValue($db, $row.composerId, $json)
      $patched++
    }
  }
  Out ("Patched value JSON rows: $patched")

  [WinSqlite3Fix]::Exec($db, 'COMMIT')

  $nOld2 = [WinSqlite3Fix]::CountWhere($db, 'SELECT COUNT(*) FROM composerHeaders WHERE workspaceId=?', $OldId, $null)
  $nNew2 = [WinSqlite3Fix]::CountWhere($db, 'SELECT COUNT(*) FROM composerHeaders WHERE workspaceId=?', $NewId, $null)
  Out '==== POST ===='
  Out ("  workspaceId=OLD: $nOld2")
  Out ("  workspaceId=NEW: $nNew2")
  foreach ($gid in $GoldIds) {
    $ws = [WinSqlite3Fix]::GetWorkspaceOf($db, $gid)
    Out ("  gold $gid : workspaceId=$ws")
  }
}
catch {
  try { [WinSqlite3Fix]::Exec($db, 'ROLLBACK') } catch {}
  throw
}
finally {
  [void][WinSqlite3Fix]::sqlite3_close($db)
}

# remove wal/shm so Cursor cannot replay old pages over our update
Remove-Item ($GlobalDb + '-wal'), ($GlobalDb + '-shm') -ErrorAction SilentlyContinue
Out 'Cleared state.vscdb-wal / -shm (if any)'
Out ''
Out ("DONE. Reopen Cursor on the same SSH host + path {0} and check History / @." -f $NewPath)
Out ("Backup: $BackupDir")
Read-Host 'Press Enter to continue'
