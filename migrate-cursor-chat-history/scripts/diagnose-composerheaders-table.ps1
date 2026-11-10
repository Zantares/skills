# READ-ONLY: composerHeaders table + migration gate flags
# Usage:
#   powershell -ExecutionPolicy Bypass -File .\diagnose-composerheaders-table.ps1 -OldId <OLD> -NewId <NEW>

param(
  [Parameter(Mandatory=$true)][string]$OldId,
  [Parameter(Mandatory=$true)][string]$NewId,
  [string[]]$GoldIds = @()
)

$ErrorActionPreference = 'Stop'

$sqliteCode = @'
using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Collections.Generic;

public static class WinSqlite3Diag {
  public const int SQLITE_OK = 0;
  public const int SQLITE_ROW = 100;
  public const int SQLITE_OPEN_READONLY = 1;
  private static readonly IntPtr SQLITE_TRANSIENT = new IntPtr(-1);

  [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
  public static extern int sqlite3_open_v2(byte[] filename, out IntPtr db, int flags, IntPtr zVfs);
  [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
  public static extern int sqlite3_close(IntPtr db);
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
  public static extern int sqlite3_column_type(IntPtr stmt, int iCol);
  [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
  public static extern long sqlite3_column_int64(IntPtr stmt, int iCol);
  [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
  public static extern IntPtr sqlite3_column_blob(IntPtr stmt, int iCol);
  [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
  public static extern int sqlite3_column_bytes(IntPtr stmt, int iCol);
  [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
  public static extern IntPtr sqlite3_errmsg(IntPtr db);

  public static byte[] Z(string s) { return Encoding.UTF8.GetBytes(s + "\0"); }
  public static string PtrToUtf8(IntPtr p) {
    if (p == IntPtr.Zero) return null;
    int len = 0; while (Marshal.ReadByte(p, len) != 0) len++;
    byte[] buf = new byte[len]; Marshal.Copy(p, buf, 0, len);
    return Encoding.UTF8.GetString(buf);
  }
  public static IntPtr Open(string path) {
    IntPtr db; int rc = sqlite3_open_v2(Z(path), out db, SQLITE_OPEN_READONLY, IntPtr.Zero);
    if (rc != SQLITE_OK) throw new Exception("open failed " + path + " rc=" + rc);
    return db;
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
  public static long Count(IntPtr db, string sql, string a) {
    IntPtr stmt; int rc = sqlite3_prepare_v2(db, Z(sql), -1, out stmt, IntPtr.Zero);
    if (rc != SQLITE_OK) throw new Exception(PtrToUtf8(sqlite3_errmsg(db)));
    try {
      if (a != null) {
        byte[] ba = Encoding.UTF8.GetBytes(a);
        sqlite3_bind_text(stmt, 1, ba, ba.Length, SQLITE_TRANSIENT);
      }
      if (sqlite3_step(stmt) != SQLITE_ROW) return -1;
      return sqlite3_column_int64(stmt, 0);
    } finally { sqlite3_finalize(stmt); }
  }
  public static string WorkspaceOf(IntPtr db, string composerId) {
    IntPtr stmt; int rc = sqlite3_prepare_v2(db, Z("SELECT workspaceId FROM composerHeaders WHERE composerId=?"), -1, out stmt, IntPtr.Zero);
    if (rc != SQLITE_OK) throw new Exception(PtrToUtf8(sqlite3_errmsg(db)));
    try {
      byte[] k = Encoding.UTF8.GetBytes(composerId);
      sqlite3_bind_text(stmt, 1, k, k.Length, SQLITE_TRANSIENT);
      if (sqlite3_step(stmt) != SQLITE_ROW) return null;
      return PtrToUtf8(sqlite3_column_text(stmt, 0));
    } finally { sqlite3_finalize(stmt); }
  }
  public static List<string> Sample(IntPtr db, string workspaceId, int limit) {
    var list = new List<string>();
    IntPtr stmt; int rc = sqlite3_prepare_v2(db, Z("SELECT composerId, isArchived, substr(value,1,120) FROM composerHeaders WHERE workspaceId=? ORDER BY recency DESC LIMIT ?"), -1, out stmt, IntPtr.Zero);
    if (rc != SQLITE_OK) throw new Exception(PtrToUtf8(sqlite3_errmsg(db)));
    try {
      byte[] k = Encoding.UTF8.GetBytes(workspaceId);
      sqlite3_bind_text(stmt, 1, k, k.Length, SQLITE_TRANSIENT);
      sqlite3_bind_int64(stmt, 2, limit);
      while (sqlite3_step(stmt) == SQLITE_ROW) {
        list.Add(PtrToUtf8(sqlite3_column_text(stmt, 0)) + " archived=" + sqlite3_column_int64(stmt, 1) + " " + PtrToUtf8(sqlite3_column_text(stmt, 2)));
      }
    } finally { sqlite3_finalize(stmt); }
    return list;
  }
  public static List<string> Tables(IntPtr db) {
    var list = new List<string>();
    IntPtr stmt; int rc = sqlite3_prepare_v2(db, Z("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"), -1, out stmt, IntPtr.Zero);
    if (rc != SQLITE_OK) throw new Exception(PtrToUtf8(sqlite3_errmsg(db)));
    try {
      while (sqlite3_step(stmt) == SQLITE_ROW) list.Add(PtrToUtf8(sqlite3_column_text(stmt, 0)));
    } finally { sqlite3_finalize(stmt); }
    return list;
  }
}
'@

Add-Type -TypeDefinition $sqliteCode -Language CSharp -ErrorAction Stop

$GlobalDb = Join-Path $env:APPDATA 'Cursor\User\globalStorage\state.vscdb'
Write-Host '==== diagnose composerHeaders table ===='
Write-Host "OldId=$OldId"
Write-Host "NewId=$NewId"
Write-Host "globalDb=$GlobalDb"

$procs = @(Get-Process | Where-Object { $_.ProcessName -like 'Cursor*' })
Write-Host ("Cursor processes: {0}" -f $procs.Count)

$db = [WinSqlite3Diag]::Open($GlobalDb)
try {
  Write-Host 'tables:'
  foreach ($t in [WinSqlite3Diag]::Tables($db)) { Write-Host "  $t" }

  $gate = [WinSqlite3Diag]::GetText($db, 'ItemTable', 'composer.composerHeaders.tableGateEnabled')
  $mig = [WinSqlite3Diag]::GetText($db, 'cursorDiskKV', 'composer.composerHeaders.migratedToTable')
  if (-not $mig) { $mig = [WinSqlite3Diag]::GetText($db, 'ItemTable', 'composer.composerHeaders.migratedToTable') }
  $ver = [WinSqlite3Diag]::GetText($db, 'ItemTable', 'composer.composerHeaders.version')
  Write-Host "tableGateEnabled=$gate migratedToTable=$mig version=$ver"

  if (-not ([WinSqlite3Diag]::Tables($db) -contains 'composerHeaders')) {
    Write-Host 'ERROR: composerHeaders table missing. This Cursor build may still use ItemTable JSON only.'
  } else {
    $nAll = [WinSqlite3Diag]::Count($db, 'SELECT COUNT(*) FROM composerHeaders', $null)
    $nOld = [WinSqlite3Diag]::Count($db, 'SELECT COUNT(*) FROM composerHeaders WHERE workspaceId=?', $OldId)
    $nNew = [WinSqlite3Diag]::Count($db, 'SELECT COUNT(*) FROM composerHeaders WHERE workspaceId=?', $NewId)
    $nOldA = [WinSqlite3Diag]::Count($db, 'SELECT COUNT(*) FROM composerHeaders WHERE workspaceId=? AND isArchived=0', $OldId)
    Write-Host "total=$nAll OLD=$nOld (active=$nOldA) NEW=$nNew"
    Write-Host 'sample OLD:'
    foreach ($s in [WinSqlite3Diag]::Sample($db, $OldId, 5)) { Write-Host "  $s" }
    Write-Host 'sample NEW:'
    foreach ($s in [WinSqlite3Diag]::Sample($db, $NewId, 5)) { Write-Host "  $s" }
  }

  foreach ($gid in $GoldIds) {
    $ws = [WinSqlite3Diag]::WorkspaceOf($db, $gid)
    if ($null -eq $ws) { Write-Host "gold $gid : NOT in composerHeaders" }
    else { Write-Host "gold $gid : workspaceId=$ws" }
  }

  $ht = [WinSqlite3Diag]::GetText($db, 'ItemTable', 'composer.composerHeaders')
  if ($ht) {
    try {
      $all = @(($ht | ConvertFrom-Json).allComposers)
      $bn = @($all | Where-Object { $_.workspaceIdentifier.id -eq $NewId }).Count
      $bo = @($all | Where-Object { $_.workspaceIdentifier.id -eq $OldId }).Count
      Write-Host ("ItemTable composer.composerHeaders JSON count={0} boundNew={1} boundOld={2} (often IGNORED when tableGateEnabled)" -f $all.Count, $bn, $bo)
    } catch {
      Write-Host 'ItemTable composer.composerHeaders present but JSON parse failed'
    }
  } else {
    Write-Host 'ItemTable composer.composerHeaders missing'
  }
}
finally {
  [void][WinSqlite3Diag]::sqlite3_close($db)
}

Write-Host ''
Write-Host 'If OLD>>0 and NEW small while History empty: run fix-composerheaders-table-workspace.ps1'
Read-Host 'Press Enter to continue'
