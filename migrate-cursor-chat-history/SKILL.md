---
name: migrate-cursor-chat-history
description: >-
  Restore Cursor IDE Chat History, @-mention list, and Agents sidebar after a
  Remote-SSH home/path rename. Discovers matching workspace ids and rebinds
  composerHeaders.workspaceId. Use when History is empty or @ only shows New
  Chat after a remote path change, while search still finds old chats.
---

# Migrate Cursor Chat History (Remote-SSH path rename)

## Goal

Same SSH host, new remote path → new workspace id. Chat bodies stay in
`%APPDATA%\Cursor\User\globalStorage\state.vscdb`. History / @ / Agents sidebar
filter on `composerHeaders.workspaceId`. Rebind that column OLD → NEW once.

## Correct model

- Live index: table **`composerHeaders`**, column **`workspaceId`**
- Pair only **same SSH host + old path ↔ new path**
- On write: `uri.authority` / `remoteAuthority` = `ssh-remote+<hex>`; folder /
  `uri.external` = `ssh-remote%2B<hex>`
- Fully quit Cursor before writing

## Main flow

```
Progress:
- [ ] 1. Discover OLD/NEW workspace ids
- [ ] 2. Verify same host + old/new paths
- [ ] 3. Bind (script derives path/authority from workspace.json)
- [ ] 4. Open same SSH host + NEW path; confirm History / @
```

### 1) Discover

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\discover-cursor-workspaces.ps1
```

### 2) Verify

One OLD and one NEW with the same `ssh-remote%2B…` host; paths are previous vs
current home. Do not merge other SSH hosts.

### 3) Bind

Cursor fully quit:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\fix-composerheaders-table-workspace.ps1 -OldId <OLD> -NewId <NEW>
```

Script reads both `workspace.json` files (rejects host mismatch), backs up
`state.vscdb`, updates `workspaceId`, patches `value` JSON with correct
authority encoding, checkpoints WAL.

### 4) Confirm

Connect via the real SSH config host → open NEW path → check History / @.

## Scripts

| Script | Purpose |
|--------|---------|
| `discover-cursor-workspaces.ps1` | List workspace ids / URIs |
| `fix-composerheaders-table-workspace.ps1` | Bind + correct authority encoding |

Example ids: [reference.md](reference.md).
