# Repair remoteAuthority / uri.authority: literal '+'.
# Folder URIs and "external" keep '%2B'. Quit Cursor first.
# Use when the SSH host label becomes ssh-remote... after a history rebind.
$ErrorActionPreference = 'Stop'
$procs = @(Get-Process | Where-Object { $_.ProcessName -like 'Cursor*' })
if ($procs.Count -gt 0) { throw 'Quit Cursor completely (no Cursor.exe), then rerun.' }

$re = [regex]'("(?:remoteAuthority|authority)"\s*:\s*")ssh-remote%(?:25)?2B'
function Repair-Text([string]$text) {
  if ([string]::IsNullOrEmpty($text)) { return $text }
  return $re.Replace($text, '${1}ssh-remote+')
}
function Show-Auth([string]$label, [string]$text) {
  Write-Host ("---- " + $label + " ----")
  $ms = [regex]::Matches($text, '"remoteAuthority"\s*:\s*"([^"]+)"')
  if ($ms.Count -eq 0) { Write-Host 'no remoteAuthority keys' }
  foreach ($m in $ms) {
    $v = $m.Groups[1].Value
    Write-Host ("remoteAuthority=" + $v)
    if ($v.StartsWith('ssh-remote+')) {
      $hex = $v.Substring(11)
      if (($hex.Length % 2 -eq 0) -and ($hex -match '^[0-9a-fA-F]+$')) {
        $bytes = New-Object byte[] ($hex.Length / 2)
        for ($i = 0; $i -lt $bytes.Length; $i++) {
          $bytes[$i] = [Convert]::ToByte($hex.Substring($i * 2, 2), 16)
        }
        Write-Host ("decoded=" + [Text.Encoding]::UTF8.GetString($bytes))
      }
    }
  }
}

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$backup = Join-Path $env:USERPROFILE ("Desktop\cursor_ssh_authority_repair_" + $stamp)
New-Item -ItemType Directory -Force -Path $backup | Out-Null
$userDir = Join-Path $env:APPDATA 'Cursor\User'
$storage = Join-Path $userDir 'globalStorage\storage.json'
$globalDb = Join-Path $userDir 'globalStorage\state.vscdb'
Copy-Item $storage (Join-Path $backup 'storage.json') -Force
Copy-Item $globalDb (Join-Path $backup 'state.vscdb') -Force

$raw = [IO.File]::ReadAllText($storage)
Show-Auth 'BEFORE storage.json' $raw
$storageHits = $re.Matches($raw).Count
$fixedStorage = Repair-Text $raw
if ($storageHits -gt 0) { [IO.File]::WriteAllText($storage, $fixedStorage) }
Write-Host ("storage.json hits rewritten: " + $storageHits)
Show-Auth 'AFTER storage.json' $fixedStorage

$wsRoot = Join-Path $userDir 'workspaceStorage'
$wsJsonHits = 0
Get-ChildItem $wsRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
  $wj = Join-Path $_.FullName 'workspace.json'
  if (Test-Path $wj) {
    $t = [IO.File]::ReadAllText($wj)
    $n = $re.Matches($t).Count
    if ($n -gt 0) {
      [IO.File]::WriteAllText($wj, (Repair-Text $t))
      $script:wsJsonHits += $n
    }
  }
}
Write-Host ("workspace.json hits rewritten: " + $wsJsonHits)

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;

public static class SqlRepair {
    const int SQLITE_OK = 0;
    const int SQLITE_ROW = 100;
    const int SQLITE_DONE = 101;
    const int SQLITE_OPEN_READWRITE = 2;
    static readonly IntPtr TRANSIENT = new IntPtr(-1);
    static readonly Regex Re = new Regex("(\"(?:remoteAuthority|authority)\"\\s*:\\s*\")ssh-remote%(?:25)?2B", RegexOptions.Compiled);

    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
    static extern int sqlite3_open_v2(byte[] filename, out IntPtr db, int flags, IntPtr zVfs);
    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
    static extern int sqlite3_close(IntPtr db);
    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
    static extern int sqlite3_exec(IntPtr db, byte[] sql, IntPtr cb, IntPtr arg, out IntPtr err);
    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
    static extern int sqlite3_prepare_v2(IntPtr db, byte[] sql, int nByte, out IntPtr stmt, IntPtr pzTail);
    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
    static extern int sqlite3_step(IntPtr stmt);
    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
    static extern int sqlite3_finalize(IntPtr stmt);
    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
    static extern int sqlite3_bind_text(IntPtr stmt, int i, byte[] val, int n, IntPtr destructor);
    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
    static extern IntPtr sqlite3_column_text(IntPtr stmt, int iCol);
    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
    static extern int sqlite3_column_bytes(IntPtr stmt, int iCol);
    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
    static extern IntPtr sqlite3_column_blob(IntPtr stmt, int iCol);
    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
    static extern int sqlite3_column_type(IntPtr stmt, int iCol);
    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
    static extern IntPtr sqlite3_errmsg(IntPtr db);

    static byte[] Z(string s) { return Encoding.UTF8.GetBytes(s + "\0"); }
    static string Ptr(IntPtr p) {
        if (p == IntPtr.Zero) return "";
        int n = 0;
        while (Marshal.ReadByte(p, n) != 0) n++;
        byte[] b = new byte[n];
        Marshal.Copy(p, b, 0, n);
        return Encoding.UTF8.GetString(b);
    }
    static void Exec(IntPtr db, string sql) {
        IntPtr err;
        int rc = sqlite3_exec(db, Z(sql), IntPtr.Zero, IntPtr.Zero, out err);
        if (rc != SQLITE_OK) throw new Exception("exec " + rc + ": " + Ptr(err));
    }
    static string Col(IntPtr stmt, int i) {
        int t = sqlite3_column_type(stmt, i);
        if (t == 3) return Ptr(sqlite3_column_text(stmt, i));
        if (t == 4) {
            int n = sqlite3_column_bytes(stmt, i);
            byte[] b = new byte[n];
            IntPtr p = sqlite3_column_blob(stmt, i);
            if (n > 0 && p != IntPtr.Zero) Marshal.Copy(p, b, 0, n);
            return Encoding.UTF8.GetString(b);
        }
        return "";
    }
    static bool TableExists(IntPtr db, string name) {
        IntPtr stmt;
        int rc = sqlite3_prepare_v2(db, Z("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?"), -1, out stmt, IntPtr.Zero);
        if (rc != SQLITE_OK) throw new Exception(Ptr(sqlite3_errmsg(db)));
        try {
            byte[] nb = Encoding.UTF8.GetBytes(name);
            sqlite3_bind_text(stmt, 1, nb, nb.Length, TRANSIENT);
            return sqlite3_step(stmt) == SQLITE_ROW;
        } finally { sqlite3_finalize(stmt); }
    }
    class Hit { public string Id; public string Value; public int Count; }
    static int RepairTable(IntPtr db, string table, string idCol, string valCol) {
        string selectSql = "SELECT " + idCol + ", " + valCol + " FROM " + table + " WHERE " + valCol + " LIKE '%ssh-remote%2B%'";
        IntPtr stmt;
        int rc = sqlite3_prepare_v2(db, Z(selectSql), -1, out stmt, IntPtr.Zero);
        if (rc != SQLITE_OK) throw new Exception(Ptr(sqlite3_errmsg(db)));
        List<Hit> hits = new List<Hit>();
        try {
            while (sqlite3_step(stmt) == SQLITE_ROW) {
                string id = Col(stmt, 0);
                string val = Col(stmt, 1);
                int n = Re.Matches(val).Count;
                if (n > 0) {
                    Hit h = new Hit();
                    h.Id = id;
                    h.Value = Re.Replace(val, "$1ssh-remote+");
                    h.Count = n;
                    hits.Add(h);
                }
            }
        } finally { sqlite3_finalize(stmt); }
        string updateSql = "UPDATE " + table + " SET " + valCol + "=? WHERE " + idCol + "=?";
        int total = 0;
        for (int i = 0; i < hits.Count; i++) {
            IntPtr ust;
            rc = sqlite3_prepare_v2(db, Z(updateSql), -1, out ust, IntPtr.Zero);
            if (rc != SQLITE_OK) throw new Exception(Ptr(sqlite3_errmsg(db)));
            try {
                byte[] vb = Encoding.UTF8.GetBytes(hits[i].Value);
                byte[] ib = Encoding.UTF8.GetBytes(hits[i].Id);
                sqlite3_bind_text(ust, 1, vb, vb.Length, TRANSIENT);
                sqlite3_bind_text(ust, 2, ib, ib.Length, TRANSIENT);
                if (sqlite3_step(ust) != SQLITE_DONE) throw new Exception(Ptr(sqlite3_errmsg(db)));
                total += hits[i].Count;
            } finally { sqlite3_finalize(ust); }
        }
        return total;
    }
    public static string RepairDatabase(string path) {
        IntPtr db;
        int rc = sqlite3_open_v2(Z(path), out db, SQLITE_OPEN_READWRITE, IntPtr.Zero);
        if (rc != SQLITE_OK) throw new Exception("open failed " + path + " rc=" + rc);
        try {
            Exec(db, "BEGIN IMMEDIATE");
            int headers = 0;
            int items = 0;
            if (TableExists(db, "composerHeaders")) headers = RepairTable(db, "composerHeaders", "composerId", "value");
            if (TableExists(db, "ItemTable")) items = RepairTable(db, "ItemTable", "key", "value");
            Exec(db, "COMMIT");
            Exec(db, "PRAGMA wal_checkpoint(TRUNCATE)");
            return "composerHeaders=" + headers + " ItemTable=" + items;
        } catch (Exception ex) {
            try { Exec(db, "ROLLBACK"); } catch (Exception) {}
            throw new Exception(path + " : " + ex.Message);
        } finally { sqlite3_close(db); }
    }
}
'@

Write-Host ("globalDb " + [SqlRepair]::RepairDatabase($globalDb))
Remove-Item ($globalDb + '-wal'), ($globalDb + '-shm') -ErrorAction SilentlyContinue
Get-ChildItem $wsRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
  $dbp = Join-Path $_.FullName 'state.vscdb'
  if (Test-Path $dbp) {
    Write-Host ($_.Name + " " + [SqlRepair]::RepairDatabase($dbp))
    Remove-Item ($dbp + '-wal'), ($dbp + '-shm') -ErrorAction SilentlyContinue
  }
}
Write-Host ("Backup: " + $backup)
Write-Host "DONE. Start Cursor, Remote-SSH: Connect to Host, choose the real SSH host, open the new home path."
