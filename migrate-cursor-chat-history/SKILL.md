---
name: migrate-cursor-chat-history
description: >-
  Restore Cursor IDE Chat History, @-mention chat list, and Agents sidebar after
  a Remote-SSH home/username/path rename (e.g. /home/old -> /home/new). Diagnoses
  workspaceStorage IDs, avoids unsafe global DB rewrites, and rebinds the
  composerHeaders SQLite table workspaceId. Use when Cursor history is empty,
  @ only shows New Chat, search still finds old chats, after luteng/teng.lu
  style path migration, or when the SSH host label becomes "ssh-remote..." and
  reconnect fails after a history rebind.
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

Authority has **two** encodings. Mixing them breaks SSH on the next launch:

| Field | Correct form | Example |
|-------|----------------|---------|
| Folder URI, `workspace.json` `folder`, `uri.external` | `vscode-remote://ssh-remote%2B<hex><path>` | keep `%2B` |
| `remoteAuthority`, `uri.authority` | `ssh-remote+<hex>` | literal `+`, never `%2B` |

`<hex>` is hex-encoded UTF-8 JSON `{"hostName":"<ssh-config Host>"}` (for `mlc09`: `7b22686f73744e616d65223a226d6c633039227d`). It is not base64.

Workspace id = hash of the full remote folder URI (host + path). Renaming `/home/old` → `/home/new` creates a **new** id even on the same SSH host.

## Hard rules

1. **Fully quit Cursor** before any DB write (no `Cursor*` processes). Clear `state.vscdb-wal` / `-shm` after restore/write.
2. **Never** mass string-replace the global DB for unequal-length paths (`luteng` vs `teng.lu`).
3. **Never** bind all global `composerData` rows into headers (e.g. “803” rewrite) — corrupts History/@.
4. **Do not** switch/replace Cursor profiles (MyConfig vs Default) to “fix” history unless `storage.json` `profileAssociations` proves the wrong profile DB is active.
5. Pair by **same SSH host + old/new path**, not every host that shares a username.
6. Prefer **backup → surgical UPDATE → verify UI**. Fail closed; do not loosen checks to mask unknown state.
7. PowerShell scripts: ASCII-only prompts + UTF-8 BOM when shipping to Windows PowerShell 5.1 (Chinese in `Read-Host` strings often parse-breaks after scp). Call .NET methods with parentheses (`[Type]::Method($a, $b)`); Windows PowerShell 5.1 rejects `[Type]::Method $a $b`.
8. **Never** write `ssh-remote%2B...` into `uri.authority` or `remoteAuthority`. That field must use a literal `+`. Folder URIs keep `%2B`. The bad form can survive the current session (`storage.json` may still decode to `mlc09`) and on the **next** start the host label becomes `ssh-remote...` and SSH fails.

## Workflow

Copy this checklist:

```
Progress:
- [ ] 1. Discover OLD/NEW workspace ids (same host)
- [ ] 2. Confirm bodies searchable; note tableGate/migratedToTable
- [ ] 3. Backup global state.vscdb (+ wal/shm)
- [ ] 4. Rebind composerHeaders.workspaceId OLD -> NEW (authority uses literal +)
- [ ] 5. Reopen SSH host + NEW path; verify History / @ / sidebar
- [ ] 6. Fully quit and start Cursor once more; if host label is ssh-remote..., run repair-ssh-authority.ps1
- [ ] 7. Only if History still broken: gold-vs-old / glass diagnose
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
4. Write `uri.authority` as `ssh-remote+<hex>` and `uri.external` as `vscode-remote://ssh-remote%2B<hex><path>`
5. Checkpoint WAL, then delete wal/shm

Then reopen **same SSH host + NEW path** and check History / @ / Agents sidebar.

Quit Cursor fully and start it **once more**. If that second start cannot SSH and the host label begins with `ssh-remote`, run the repair below before doing anything else. Do not restore the pre-repair DB just to undo it: that backup still has the bad `%2B` authority fields.

### 4) Repair SSH authority (if the next start shows `ssh-remote...`)

Cause: header / ItemTable JSON stored `uri.authority` as `ssh-remote%2B<hex>`. `storage.json` `remoteAuthority` may still be the good `ssh-remote+<hex>` form (decodes to `{"hostName":"mlc09"}`). Cursor then displays the raw authority and fails the connection.

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\repair-ssh-authority.ps1
```

Expect `decoded={"hostName":"<ssh host>"}`. `storage.json` hit count may be 0. `composerHeaders` / `ItemTable` hit counts are the rows that had `%2B` in an authority field.

Then **Remote-SSH: Connect to Host** → the real SSH config host (example `mlc09`) → open the new path. Do not click a recent entry whose name starts with `ssh-remote`.

### 5) Rollback

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
| Put `ssh-remote%2B...` in `uri.authority` | Next Cursor start shows host `ssh-remote...` and SSH fails |

## Optional / deferred

- Patching every `composerData:*` body’s `workspaceIdentifier` — only if a specific chat opens wrong after table rebind
- `glass.localAgentProjects.v1` / membership — only if Agents sidebar still wrong after table fix
- Rewriting absolute paths inside settings/conda — separate from History

## Cleanup after a successful History fix

Safe to delete once UI is stable for a few days: intermediate Desktop `cursor_*backup_*` / diagnose dump folders **except** keep `cursor_composerHeaders_table_backup_*` (pre-table-fix) until confident. Remote `cursor_migrate_*.log*` are disposable. Keep `cursor_ssh_authority_repair_*` until SSH is confirmed stable across a full quit/reopen.

## Scripts

All under [scripts/](scripts/). Run on **Windows** against `%APPDATA%\Cursor`. Copy from this skill dir (or scp from a machine that has the store synced).

| Script | Mode | Purpose |
|--------|------|---------|
| `discover-cursor-workspaces.ps1` | read | List workspace ids / URIs / db sizes |
| `diagnose-composerheaders-table.ps1` | read | Counts by workspaceId; gate flags |
| `diagnose-history-gold-vs-old.ps1` | read | Compare post-migrate chat vs old |
| `fix-composerheaders-table-workspace.ps1` | write | Canonical History/@ rebind. `uri.authority` gets literal `+`; `external` keeps `%2B` |
| `repair-ssh-authority.ps1` | write | Rewrite only `remoteAuthority` / `uri.authority` from `ssh-remote%2B` to `ssh-remote+` |
| `restore-cursor-vscdb-backup.ps1` | write | Restore a Desktop `*.vscdb` backup |

Details and incident notes: [reference.md](reference.md).
