# Reference: Cursor chat History after path rename

## Example incident (mlc09)

| Role | Value |
|------|--------|
| SSH host | `mlc09` |
| OLD path | `/home/luteng` |
| NEW path | `/home/teng.lu` |
| OLD workspace id | `fcb79932691a7c545711254f250a7d1e` |
| NEW workspace id | `5922db438f27b34d5a63fe374333a8f5` |
| Folder URI authority | `ssh-remote%2B7b22686f73744e616d65223a226d6c633039227d` |
| Parsed `remoteAuthority` / `uri.authority` | `ssh-remote+7b22686f73744e616d65223a226d6c633039227d` |
| Hex decodes to | `{"hostName":"mlc09"}` |

Symptoms before fix: Search found old chats; History/@ empty or only New Chat; Agents sidebar split / missing.

Failed attempts: workspace `state.vscdb` copy; ItemTable `composer.composerHeaders` reindex (77 then 803); MyConfig profile experiments; global mass replace.

Working fix: `UPDATE composerHeaders SET workspaceId=<NEW> WHERE workspaceId=<OLD>` (~163 rows), with backup. UI History/@/sidebar restored; host projects merged under new path.

## SSH regression after that fix (2026-11-11)

The value-JSON patch wrote `uri.authority = ssh-remote%2B<hex>` (the folder-URI encoding) into 165 `composerHeaders` rows and 79 `ItemTable` values. `storage.json` `remoteAuthority` stayed `ssh-remote+<hex>` and still decoded to `{"hostName":"mlc09"}`.

The session that applied the patch could still SSH. The **next** Cursor start showed the host as `ssh-remote...` and could not connect.

Repair (Cursor fully quit): `scripts/repair-ssh-authority.ps1`. It rewrites only `"authority"` / `"remoteAuthority"` values from `ssh-remote%2B` or `ssh-remote%252B` to `ssh-remote+`. It does not touch `external` or folder URIs. Observed result: `storage.json` hits 0, global `composerHeaders` 165, `ItemTable` 79. Then Connect to Host → `mlc09` → `/home/teng.lu`. SSH worked.

Do not cover the global DB with `cursor_composerHeaders_table_backup_*` or `cursor_ssh_authority_repair_*` taken **before** this repair; those copies still contain the bad authority fields (the repair backup is the pre-repair snapshot).

`fix-composerheaders-table-workspace.ps1` now derives a literal-`+` authority for `uri.authority` and keeps `%2B` only in `uri.external`.

## composerHeaders table (observed)

Columns (abbrev.): `composerId`, `workspaceId`, `createdAt`, `lastUpdatedAt`, `isArchived`, `isSubagent`, `recency`, `checkpointAt`, `value` (JSON head), `subagentTypeName`.

UI filter: current window workspace id ≈ `workspaceId`.

Flags in ItemTable / cursorDiskKV:

- `composer.composerHeaders.tableGateEnabled` = `true`
- `composer.composerHeaders.migratedToTable` = `1`
- `composer.composerHeaders.version` = timestamp-ish string

## Gold-chat diagnostic pattern

1. Create 1–2 chats **after** opening the NEW workspace.
2. Quit Cursor; dump whether those composer ids appear in `composerHeaders` and with which `workspaceId`.
3. If a new chat appears in History but is **absent** from ItemTable JSON headers, the table (or glass) is the real index.
4. Diff old chat `composerData.workspaceIdentifier` (often still OLD path) vs new chat (NEW path). Body mismatch alone did not block list once table `workspaceId` was corrected.

## Backup naming (suggested)

- `Desktop\cursor_composerHeaders_table_backup_<timestamp>\state.vscdb`
- `Desktop\cursor_ssh_authority_repair_<timestamp>\` (pre-authority-repair snapshot)
- Always delete `state.vscdb-wal` / `state.vscdb-shm` after restore or surgical write

## Related remote-side notes

- Agent transcripts under `~/.cursor/projects/<slug>/agent-transcripts` are separate from Windows History index; merging remote projects does not restore IDE History by itself.
- Conda/shebang path rewrites are orthogonal to chat History index.
