---
name: migrate-cursor-chat-history
description: >-
  Restore Cursor IDE Chat History, @-mention chat list, and Agents sidebar after
  a Remote-SSH home/username/path rename (e.g. /home/old -> /home/new). Diagnoses
  workspaceStorage IDs, avoids unsafe global DB rewrites, and rebinds the
  composerHeaders SQLite table workspaceId. Use when Cursor history is empty,
  @ only shows New Chat, search still finds old chats, or after luteng/teng.lu
  style path migration.
---

# Migrate Cursor Chat History (Remote-SSH path rename)

## Goal

After the remote folder URI changes (same SSH host, new home path), chat **bodies** usually remain in Windows `%APPDATA%\Cursor\User\globalStorage\state.vscdb`, but **History / @ / Agents sidebar** filter by workspace id and stop listing old chats.

## Storage model (must know)

| What | Where | Role |
|------|--------|------|
| Chat bodies | `globalStorage\state.vscdb` → `cursorDiskKV` keys `composerData:*`, `bubbleId:*` | Search / open content |
| History / @ index (current Cursor) | Same DB → SQLite table **`composerHeaders`** column **`workspaceId`** | UI list filter |
| Legacy JSON index | `ItemTable` key `composer.composerHeaders` | Often **ignored** when `composer.composerHeaders.tableGateEnabled=true` and `migratedToTable=1` |
| Workspace selection | `workspaceStorage\<hash>\state.vscdb` → `composer.composerData` | selected/lastFocused ids |
| Workspace identity | `workspaceStorage\<hash>\workspace.json` | `folder` URI → hash id |

Remote URI must keep encoded authority: `ssh-remote%2B<base64json>` (do not turn `%2B` into `+`).

Workspace id = hash of the full remote folder URI (host + path). Renaming `/home/old` → `/home/new` creates a **new** id even on the same SSH host.

## Hard rules

1. **Fully quit Cursor** before any DB write (no `Cursor*` processes). Clear `state.vscdb-wal` / `-shm` after restore/write.
2. **Never** mass string-replace the global DB for unequal-length paths (`luteng` vs `teng.lu`).
3. **Never** bind all global `composerData` rows into headers (e.g. “803” rewrite) — corrupts History/@.
4. **Do not** switch/replace Cursor profiles (MyConfig vs Default) to “fix” history unless `storage.json` `profileAssociations` proves the wrong profile DB is active.
5. Pair by **same SSH host + old/new path**, not every host that shares a username.
6. Prefer **backup → surgical UPDATE → verify UI**. Fail closed; do not loosen checks to mask unknown state.
7. PowerShell scripts: ASCII-only prompts + UTF-8 BOM when shipping to Windows PowerShell 5.1 (Chinese in `Read-Host` strings often parse-breaks after scp).

## Workflow

Copy this checklist:

```
Progress:
- [ ] 1. Discover OLD/NEW workspace ids (same host)
- [ ] 2. Confirm bodies searchable; note tableGate/migratedToTable
- [ ] 3. Backup global state.vscdb (+ wal/shm)
- [ ] 4. Rebind composerHeaders.workspaceId OLD -> NEW
- [ ] 5. Reopen mlc-host + NEW path; verify History / @ / sidebar
- [ ] 6. Only if still broken: gold-vs-old / glass diagnose
```

### 1) Discover workspace pair

On Windows (Cursor quit optional for read-only):

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\discover-cursor-workspaces.ps1
```

Or inspect `%APPDATA%\Cursor\User\workspaceStorage\*\workspace.json` and pick:

- **OLD**: same `ssh-remote%2B…` host, old path
- **NEW**: same host, new path

Confirm in `%APPDATA%\Cursor\User\globalStorage\storage.json` → `profileAssociations.workspaces` which profile the NEW URI uses (`__default__profile__` vs named profile).

### 2) Confirm root cause before writing

Read-only:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\diagnose-composerheaders-table.ps1 -OldId <OLD> -NewId <NEW>
```

Expect when broken:

- `tableGateEnabled=true`, `migratedToTable=1`
- Many `composerHeaders` rows with `workspaceId=OLD`
- Few/none with `workspaceId=NEW` (except chats created after rename)
- ItemTable JSON `composer.composerHeaders` may already look “fixed” — **irrelevant** if table gate is on

Optional gold compare (pass post-migrate chat composer ids):

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\diagnose-history-gold-vs-old.ps1 -OldId <OLD> -NewId <NEW> -GoldIds <id1,id2>
```

### 3) Fix (canonical)

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\fix-composerheaders-table-workspace.ps1 -OldId <OLD> -NewId <NEW>
```

Does:

1. Backup `state.vscdb` to Desktop
2. `UPDATE composerHeaders SET workspaceId=NEW WHERE workspaceId=OLD`
3. Patch `value` JSON if it still embeds old workspaceIdentifier/path
4. Delete wal/shm

Then reopen **same SSH host + NEW path** and check History / @ / Agents sidebar.

### 4) Rollback

Restore the Desktop backup `state.vscdb`, delete wal/shm, reopen Cursor.

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\restore-cursor-vscdb-backup.ps1
```

## What usually does NOT fix History

| Approach | Why it fails |
|----------|----------------|
| Copy only `workspaceStorage\NEW\state.vscdb` from OLD | Bodies stay; list still filtered by `composerHeaders.workspaceId` |
| Rewrite ItemTable `composer.composerHeaders` only | Ignored when migrated to table |
| Bind every composerData id into headers | Pollutes index; can hide even New Chat |
| Global unequal-length path replace | Corrupts KV / JSON |
| Swap MyConfig profile DB blindly | Wrong DB or wipes associations |

## Optional / deferred

- Patching every `composerData:*` body’s `workspaceIdentifier` — only if a specific chat opens wrong after table rebind
- `glass.localAgentProjects.v1` / membership — only if Agents sidebar still wrong after table fix
- Rewriting absolute paths inside settings/conda — separate from History

## Scripts

All under [scripts/](scripts/). Run on **Windows** against `%APPDATA%\Cursor`. Copy from this skill dir (or scp from a machine that has the store synced).

| Script | Mode | Purpose |
|--------|------|---------|
| `discover-cursor-workspaces.ps1` | read | List workspace ids / URIs / db sizes |
| `diagnose-composerheaders-table.ps1` | read | Counts by workspaceId; gate flags |
| `diagnose-history-gold-vs-old.ps1` | read | Compare post-migrate chat vs old |
| `fix-composerheaders-table-workspace.ps1` | write | Canonical History/@ rebind |
| `restore-cursor-vscdb-backup.ps1` | write | Restore a Desktop `*.vscdb` backup |

Details and incident notes: [reference.md](reference.md).
