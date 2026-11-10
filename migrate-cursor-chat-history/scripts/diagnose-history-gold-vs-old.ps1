# =============================================================================
# READ-ONLY: compare gold (post-migrate New Chat) vs old chats for History/@
# Does NOT write any DB. Safe to re-run.
#
# Gold IDs (post-migrate chats you created):
#   a8ec64b2-9515-4ac2-8315-e8ea6b3fa82d
#   91d4809e-0b30-447e-a83b-bfe8e54a72d3  (this session; may also exist in old set)
#
# Pair:
#   OLD: fcb79932691a7c545711254f250a7d1e  (mlc09 /home/luteng)
#   NEW: 5922db438f27b34d5a63fe374333a8f5  (mlc09 /home/teng.lu)
#
# Prefer: fully quit Cursor first (cleaner snapshot; avoids WAL lag).
# Usage:
#   powershell -ExecutionPolicy Bypass -File .\diagnose-history-gold-vs-old.ps1
# =============================================================================

param(
  [Parameter(Mandatory=$true)][string]$OldId,
  [Parameter(Mandatory=$true)][string]$NewId,
  [Parameter(Mandatory=$true)][string[]]$GoldIds
)

$ErrorActionPreference = 'Stop'

$sqliteCode = @'
using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Collections.Generic;

public static class WinSqlite3 {
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
  public static extern IntPtr sqlite3_column_text(IntPtr stmt, int iCol);
  [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
  public static extern int sqlite3_column_bytes(IntPtr stmt, int iCol);
  [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
  public static extern IntPtr sqlite3_column_blob(IntPtr stmt, int iCol);
  [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
  public static extern int sqlite3_column_type(IntPtr stmt, int iCol);
  [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
  public static extern int sqlite3_bind_text(IntPtr stmt, int i, byte[] val, int n, IntPtr destructor);
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
  public static bool Exists(IntPtr db, string table, string key) {
    return GetText(db, table, key) != null;
  }
  public static List<string> ListKeysLike(IntPtr db, string table, string like) {
    var list = new List<string>();
    IntPtr stmt; int rc = sqlite3_prepare_v2(db, Z("SELECT key FROM " + table + " WHERE key LIKE ? ORDER BY key"), -1, out stmt, IntPtr.Zero);
    if (rc != SQLITE_OK) throw new Exception(PtrToUtf8(sqlite3_errmsg(db)));
    try {
      byte[] p = Encoding.UTF8.GetBytes(like);
      sqlite3_bind_text(stmt, 1, p, p.Length, SQLITE_TRANSIENT);
      while (sqlite3_step(stmt) == SQLITE_ROW) list.Add(PtrToUtf8(sqlite3_column_text(stmt, 0)));
    } finally { sqlite3_finalize(stmt); }
    return list;
  }
  public static List<string> ListKeysContaining(IntPtr db, string table, string needle) {
    var list = new List<string>();
    IntPtr stmt; int rc = sqlite3_prepare_v2(db, Z("SELECT key FROM " + table + " WHERE key LIKE ? ORDER BY key"), -1, out stmt, IntPtr.Zero);
    if (rc != SQLITE_OK) throw new Exception(PtrToUtf8(sqlite3_errmsg(db)));
    try {
      byte[] p = Encoding.UTF8.GetBytes("%" + needle + "%");
      sqlite3_bind_text(stmt, 1, p, p.Length, SQLITE_TRANSIENT);
      while (sqlite3_step(stmt) == SQLITE_ROW) list.Add(PtrToUtf8(sqlite3_column_text(stmt, 0)));
    } finally { sqlite3_finalize(stmt); }
    return list;
  }
}
'@

Add-Type -TypeDefinition $sqliteCode -Language CSharp -ErrorAction Stop

function Out([string]$s) {
  Write-Host $s
  Add-Content -Path $script:OutFile -Value $s
}
function OutJson($obj, [int]$Depth = 12) {
  $j = $obj | ConvertTo-Json -Depth $Depth -Compress:$false
  Out $j
}
function PropNames($obj) {
  if ($null -eq $obj) { return @() }
  return @($obj.PSObject.Properties.Name)
}
function Get-Prop($obj, [string]$name) {
  if ($null -eq $obj) { return $null }
  $p = $obj.PSObject.Properties[$name]
  if ($null -eq $p) { return $null }
  return $p.Value
}
function Summarize-Header($h) {
  if ($null -eq $h) { return '<null>' }
  $id = [string](Get-Prop $h 'composerId')
  $name = [string](Get-Prop $h 'name')
  $wid = [string](Get-Prop (Get-Prop $h 'workspaceIdentifier') 'id')
  $auth = $null
  $path = $null
  $ext = $null
  try { $auth = [string]$h.workspaceIdentifier.uri.authority } catch {}
  try { $path = [string]$h.workspaceIdentifier.uri.path } catch {}
  try { $ext = [string]$h.workspaceIdentifier.uri.external } catch {}
  $created = Get-Prop $h 'createdAt'
  $updated = Get-Prop $h 'lastUpdatedAt'
  $draft = Get-Prop $h 'isDraft'
  $arch = Get-Prop $h 'isArchived'
  $keys = (PropNames $h) -join ','
  return ("id={0} name={1} ws={2} auth={3} path={4} draft={5} arch={6} created={7} updated={8}`n  keys=[{9}]`n  external={10}" -f `
    $id, $name, $wid, $auth, $path, $draft, $arch, $created, $updated, $keys, $ext)
}
function Diff-Keys($gold, $old) {
  $gk = PropNames $gold
  $ok = PropNames $old
  $onlyG = @($gk | Where-Object { $_ -notin $ok })
  $onlyO = @($ok | Where-Object { $_ -notin $gk })
  $both = @($gk | Where-Object { $_ -in $ok })
  Out ("  keys only in GOLD: {0}" -f ($(if ($onlyG) { $onlyG -join ', ' } else { '(none)' })))
  Out ("  keys only in OLD : {0}" -f ($(if ($onlyO) { $onlyO -join ', ' } else { '(none)' })))
  foreach ($k in $both) {
    if ($k -eq 'workspaceIdentifier') {
      $gw = Get-Prop $gold $k | ConvertTo-Json -Depth 8 -Compress
      $ow = Get-Prop $old $k | ConvertTo-Json -Depth 8 -Compress
      if ($gw -ne $ow) {
        Out ("  DIFF workspaceIdentifier:")
        Out ("    GOLD: $gw")
        Out ("    OLD : $ow")
      } else {
        Out "  workspaceIdentifier: SAME"
      }
      continue
    }
    $gv = Get-Prop $gold $k
    $ov = Get-Prop $old $k
    $gs = if ($null -eq $gv) { '<null>' } else { "$gv" }
    $os = if ($null -eq $ov) { '<null>' } else { "$ov" }
    if ($gs -ne $os) {
      # skip huge values
      if ($gs.Length -gt 120) { $gs = $gs.Substring(0,120) + '...' }
      if ($os.Length -gt 120) { $os = $os.Substring(0,120) + '...' }
      Out ("  DIFF {0}: GOLD=[{1}] OLD=[{2}]" -f $k, $gs, $os)
    }
  }
}
function Summarize-ComposerData($txt, [string]$label) {
  Out ("--- composerData body: $label ---")
  if (-not $txt) { Out '  MISSING'; return $null }
  try { $o = $txt | ConvertFrom-Json } catch { Out ("  JSON parse fail: $_"); return $null }
  $keys = (PropNames $o) -join ','
  Out ("  topKeys=[{0}]" -f $keys)
  foreach ($f in @('composerId','name','status','unifiedMode','isDraft','isArchived','createdAt','lastUpdatedAt','subtitle','text','richText','conversationState','context','workspaceIdentifier','workspaceId','folder','uri','agentId','agentSessionId','glass','selectedContext')) {
    if ((PropNames $o) -contains $f) {
      $v = Get-Prop $o $f
      $s = if ($null -eq $v) { '<null>' } elseif ($v -is [string]) { $v } else { ($v | ConvertTo-Json -Depth 4 -Compress) }
      if ($s.Length -gt 220) { $s = $s.Substring(0,220) + '...' }
      Out ("  {0}={1}" -f $f, $s)
    }
  }
  return $o
}

$CursorUser = Join-Path $env:APPDATA 'Cursor\User'
$GlobalDb = Join-Path $CursorUser 'globalStorage\state.vscdb'
$NewWsDb = Join-Path $CursorUser "workspaceStorage\$NewId\state.vscdb"
$OldWsDb = Join-Path $CursorUser "workspaceStorage\$OldId\state.vscdb"
$Stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$script:OutFile = Join-Path $env:USERPROFILE "Desktop\cursor_history_gold_diagnose_$Stamp.txt"
$DumpDir = Join-Path $env:USERPROFILE "Desktop\cursor_history_gold_diagnose_$Stamp"
New-Item -ItemType Directory -Path $DumpDir -Force | Out-Null
'' | Set-Content -Path $script:OutFile -Encoding UTF8

Out '==== READ-ONLY History gold vs old diagnose ===='
Out ("time=$Stamp")
Out ("globalDb=$GlobalDb exists=$(Test-Path $GlobalDb)")
if (Test-Path $GlobalDb) {
  $gi = Get-Item $GlobalDb
  Out ("  size={0:N0} mtime={1}" -f $gi.Length, $gi.LastWriteTime)
}
Out ("newWsDb=$NewWsDb exists=$(Test-Path $NewWsDb)")
Out ("oldWsDb=$OldWsDb exists=$(Test-Path $OldWsDb)")
Out ("goldIds=$($GoldIds -join ', ')")
Out ("dumpDir=$DumpDir")
Out ''

# ---- Cursor process check ----
$procs = @(Get-Process | Where-Object { $_.ProcessName -like 'Cursor*' })
Out ("Cursor processes running: {0}" -f $procs.Count)
if ($procs.Count -gt 0) {
  Out '  WARNING: Cursor still running. Snapshot may lag behind UI (WAL). Prefer full quit for definitive dump.'
}
Out ''

if (-not (Test-Path $GlobalDb)) { throw "Missing global DB: $GlobalDb" }

$gdb = [WinSqlite3]::Open($GlobalDb)
try {
  # ---- 1) Headers overview ----
  Out '==== 1) composer.composerHeaders overview ===='
  $ht = [WinSqlite3]::GetText($gdb, 'ItemTable', 'composer.composerHeaders')
  if (-not $ht) {
    Out 'MISSING composer.composerHeaders'
    $all = @()
  } else {
    $hobj = $ht | ConvertFrom-Json
    $all = @($hobj.allComposers)
    Out ("totalHeaders={0}" -f $all.Count)
    $boundNew = @($all | Where-Object { $_.workspaceIdentifier.id -eq $NewId })
    $boundOld = @($all | Where-Object { $_.workspaceIdentifier.id -eq $OldId })
    $boundOther = @($all | Where-Object { $_.workspaceIdentifier.id -ne $NewId -and $_.workspaceIdentifier.id -ne $OldId })
    Out ("boundNew($NewId)={0}" -f $boundNew.Count)
    Out ("boundOld($OldId)={0}" -f $boundOld.Count)
    Out ("boundOther={0}" -f $boundOther.Count)

    $authOk = 0; $authBad = 0; $pathNew = 0; $pathOld = 0
    foreach ($c in $boundNew) {
      $a = $null; $p = $null
      try { $a = [string]$c.workspaceIdentifier.uri.authority } catch {}
      try { $p = [string]$c.workspaceIdentifier.uri.path } catch {}
      if ($a -like '*ssh-remote%2B*') { $authOk++ } else { $authBad++ }
      if ($p -eq '/home/teng.lu') { $pathNew++ }
      elseif ($p -eq '/home/luteng') { $pathOld++ }
    }
    Out ("boundNew authEncoded(%2B)={0} authUnescaped/other={1}" -f $authOk, $authBad)
    Out ("boundNew path /home/teng.lu={0} /home/luteng={1}" -f $pathNew, $pathOld)
  }
  Out ''

  # ---- 2) Locate gold headers ----
  Out '==== 2) GOLD chat headers (must exist if History/@ shows them) ===='
  $goldHeaders = @{}
  foreach ($gid in $GoldIds) {
    $hit = @($all | Where-Object { [string]$_.composerId -eq $gid })
    Out ("--- gold $gid ---")
    if ($hit.Count -eq 0) {
      Out '  NOT in composer.composerHeaders'
    } else {
      foreach ($h in $hit) {
        Out (Summarize-Header $h)
        $goldHeaders[$gid] = $h
        $dump = Join-Path $DumpDir ("gold_header_$gid.json")
        ($h | ConvertTo-Json -Depth 12) | Set-Content -Path $dump -Encoding UTF8
        Out ("  dumped -> $dump")
      }
    }
    # also search disk KV keys containing this id
    $keys = [WinSqlite3]::ListKeysContaining($gdb, 'cursorDiskKV', $gid)
    if ($keys.Count -eq 0) {
      # try ItemTable too
      $keys = [WinSqlite3]::ListKeysContaining($gdb, 'ItemTable', $gid)
      Out ("  ItemTable keys containing id: {0}" -f $keys.Count)
    } else {
      Out ("  cursorDiskKV keys containing id: {0}" -f $keys.Count)
    }
    foreach ($k in ($keys | Select-Object -First 20)) { Out ("    $k") }
    if ($keys.Count -gt 20) { Out ("    ... +$($keys.Count-20) more") }

    $cdKey = "composerData:$gid"
    $cd = [WinSqlite3]::GetText($gdb, 'cursorDiskKV', $cdKey)
    if (-not $cd) { $cd = [WinSqlite3]::GetText($gdb, 'ItemTable', $cdKey) }
    $null = Summarize-ComposerData $cd $cdKey
    if ($cd) {
      $dump = Join-Path $DumpDir ("gold_composerData_$gid.json")
      # pretty if possible
      try { ($cd | ConvertFrom-Json | ConvertTo-Json -Depth 20) | Set-Content $dump -Encoding UTF8 }
      catch { $cd | Set-Content $dump -Encoding UTF8 }
      Out ("  dumped -> $dump")
    }
    Out ''
  }

  # ---- 3) Sample old chat header (from old workspace bind OR known old id) ----
  Out '==== 3) OLD chat sample (for field-by-field diff vs GOLD) ===='
  $oldSample = $null
  # Prefer an old-bound header that is NOT a gold id
  $oldCandidates = @($all | Where-Object {
      $_.workspaceIdentifier.id -eq $OldId -and ([string]$_.composerId -notin $GoldIds)
    })
  if ($oldCandidates.Count -eq 0) {
    # fall back: any non-gold with luteng in path/external, or from known reindex sample
    $oldCandidates = @($all | Where-Object {
        ([string]$_.composerId -notin $GoldIds) -and (
          ([string](Get-Prop $_.workspaceIdentifier 'id') -eq $OldId) -or
          (([string]$_.workspaceIdentifier.uri.path) -eq '/home/luteng') -or
          (([string]$_.workspaceIdentifier.uri.external) -like '*/home/luteng')
        )
      })
  }
  if ($oldCandidates.Count -eq 0) {
    # last resort: pick a non-gold bound to NewId that we suspect was rewritten (has empty name etc.)
    Out '  No OldId-bound headers found. Will pick a non-gold NewId-bound sample if any.'
    $oldCandidates = @($boundNew | Where-Object { [string]$_.composerId -notin $GoldIds } | Select-Object -First 5)
  }
  if ($oldCandidates.Count -gt 0) {
    $oldSample = $oldCandidates[0]
    Out (Summarize-Header $oldSample)
    $oid = [string]$oldSample.composerId
    $dump = Join-Path $DumpDir ("old_header_$oid.json")
    ($oldSample | ConvertTo-Json -Depth 12) | Set-Content $dump -Encoding UTF8
    Out ("  dumped -> $dump")
    $cdKey = "composerData:$oid"
    $cd = [WinSqlite3]::GetText($gdb, 'cursorDiskKV', $cdKey)
    if (-not $cd) { $cd = [WinSqlite3]::GetText($gdb, 'ItemTable', $cdKey) }
    $null = Summarize-ComposerData $cd $cdKey
  } else {
    Out '  No old sample found in headers.'
  }
  Out ''

  # ---- 4) Field diff ----
  Out '==== 4) Field diff: GOLD vs OLD header ===='
  $primaryGold = $null
  if ($goldHeaders.ContainsKey('a8ec64b2-9515-4ac2-8315-e8ea6b3fa82d')) {
    $primaryGold = $goldHeaders['a8ec64b2-9515-4ac2-8315-e8ea6b3fa82d']
    Out 'Using GOLD = a8ec64b2... (clear post-migrate New Chat)'
  } elseif ($goldHeaders.Count -gt 0) {
    $primaryGold = @($goldHeaders.Values)[0]
    Out ("Using GOLD = {0}" -f $primaryGold.composerId)
  } else {
    Out 'NO GOLD HEADER FOUND — cannot diff. If UI shows these chats, History may NOT use composer.composerHeaders.'
  }
  if ($primaryGold -and $oldSample) {
    Diff-Keys $primaryGold $oldSample
  }
  Out ''

  # ---- 5) Workspace selected / allComposers ----
  Out '==== 5) Workspace composer.composerData (selected / allComposers) ===='
  foreach ($pair in @(@('NEW', $NewWsDb), @('OLD', $OldWsDb))) {
    $label = $pair[0]; $path = $pair[1]
    Out ("--- $label $path ---")
    if (-not (Test-Path $path)) { Out '  missing db'; continue }
    $wdb = [WinSqlite3]::Open($path)
    try {
      $wt = [WinSqlite3]::GetText($wdb, 'ItemTable', 'composer.composerData')
      if (-not $wt) { Out '  composer.composerData MISSING'; continue }
      $wo = $wt | ConvertFrom-Json
      $nAll = if ($wo.allComposers) { @($wo.allComposers).Count } else { 0 }
      $sel = @($wo.selectedComposerIds)
      $last = @($wo.lastFocusedComposerIds)
      Out ("  allComposers={0} selected={1} lastFocused={2} hasMigrated={3}" -f `
        $nAll, $sel.Count, $last.Count, $wo.hasMigratedComposerData)
      Out ("  selected: $($sel -join ', ')")
      Out ("  lastFocused: $($last -join ', ')")
      foreach ($gid in $GoldIds) {
        $inSel = $gid -in $sel
        $inLast = $gid -in $last
        Out ("  gold {0}: inSelected={1} inLastFocused={2}" -f $gid, $inSel, $inLast)
      }
      $dump = Join-Path $DumpDir ("workspace_${label}_composerData.json")
      ($wo | ConvertTo-Json -Depth 12) | Set-Content $dump -Encoding UTF8
      Out ("  dumped -> $dump")
    } finally { [void][WinSqlite3]::sqlite3_close($wdb) }
  }
  Out ''

  # ---- 6) Glass / Agents related keys ----
  Out '==== 6) Glass / Agents index keys (ItemTable + cursorDiskKV) ===='
  foreach ($table in @('ItemTable', 'cursorDiskKV')) {
    $gkeys = [WinSqlite3]::ListKeysLike($gdb, $table, 'glass%')
    $akeys = [WinSqlite3]::ListKeysLike($gdb, $table, '%agent%')
    $ckeys = [WinSqlite3]::ListKeysLike($gdb, $table, '%composerHeader%')
    $lkeys = [WinSqlite3]::ListKeysLike($gdb, $table, '%localAgent%')
    Out ("-- $table --")
    Out ("  glass*: {0}" -f $gkeys.Count)
    foreach ($k in ($gkeys | Select-Object -First 40)) { Out "    $k" }
    if ($gkeys.Count -gt 40) { Out ("    ... +$($gkeys.Count-40) more") }
    Out ("  *localAgent*: {0}" -f $lkeys.Count)
    foreach ($k in $lkeys) { Out "    $k" }
    Out ("  *composerHeader*: {0}" -f $ckeys.Count)
    foreach ($k in $ckeys) { Out "    $k" }
    # dump interesting glass values (truncated)
    foreach ($k in @($gkeys + $lkeys | Select-Object -Unique)) {
      if ($k -match 'localAgentProjects|agentProjects|composerHeaders|chatHeaders|history') {
        $txt = [WinSqlite3]::GetText($gdb, $table, $k)
        $safe = ($k -replace '[\\/:*?<>|"]', '_')
        $dump = Join-Path $DumpDir ("${table}__$safe.json")
        if ($txt) {
          try { ($txt | ConvertFrom-Json | ConvertTo-Json -Depth 20) | Set-Content $dump -Encoding UTF8 }
          catch { $txt.Substring(0, [Math]::Min(50000, $txt.Length)) | Set-Content $dump -Encoding UTF8 }
          Out ("  dumped $table::$k -> $dump (len=$($txt.Length))")
          # check if gold ids appear
          foreach ($gid in $GoldIds) {
            if ($txt.Contains($gid)) { Out ("    CONTAINS gold $gid") }
          }
          if ($txt.Contains($OldId)) { Out "    CONTAINS OldId" }
          if ($txt.Contains($NewId)) { Out "    CONTAINS NewId" }
          if ($txt.Contains('/home/luteng')) { Out "    CONTAINS /home/luteng" }
          if ($txt.Contains('/home/teng.lu')) { Out "    CONTAINS /home/teng.lu" }
        }
      }
    }
  }
  Out ''

  # ---- 7) Judgment checklist ----
  Out '==== 7) Judgment checklist (fill from above) ===='
  $g1 = $goldHeaders.ContainsKey('a8ec64b2-9515-4ac2-8315-e8ea6b3fa82d')
  $g2 = $goldHeaders.ContainsKey('91d4809e-0b30-447e-a83b-bfe8e54a72d3')
  Out ("A. Gold a8ec64b2 in composer.composerHeaders?  -> $g1")
  Out ("B. Gold 91d4809e in composer.composerHeaders?  -> $g2")
  if ($g1 -or $g2) {
    Out '   If TRUE and those chats DO appear in History/@: headers ARE the index surface.'
    Out '   Then next fix = rewrite OLD entries to match GOLD workspaceIdentifier exactly (not 803 mass-bind).'
  } else {
    Out '   If FALSE but those chats STILL appear in History/@: History/@ is NOT driven by composer.composerHeaders.'
    Out '   Then look at Glass dumps in section 6 / dumpDir.'
  }
  Out 'C. Compare GOLD vs OLD header keys (section 4): any only-in-GOLD fields = likely required.'
  Out 'D. Gold in workspace selectedComposerIds? (section 5)'
  Out 'E. Glass keys contain NewId + gold ids? (section 6)'
  Out ''
  Out 'DONE (read-only).'
  Out ("Report: $script:OutFile")
  Out ("Dumps:  $DumpDir")
}
finally {
  [void][WinSqlite3]::sqlite3_close($gdb)
}

Write-Host ''
Write-Host 'Paste Desktop cursor_history_gold_diagnose_*.txt back into chat (sections 2/4/6/7).' -ForegroundColor Cyan
Read-Host 'Press Enter to continue'
