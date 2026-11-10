# Reference

## Example pair (mlc09)

| Role | Value |
|------|--------|
| SSH host | `mlc09` |
| OLD path | `/home/luteng` |
| NEW path | `/home/teng.lu` |
| OLD workspace id | `fcb79932691a7c545711254f250a7d1e` |
| NEW workspace id | `5922db438f27b34d5a63fe374333a8f5` |

Authority forms for that host:

- folder / `external`: `ssh-remote%2B7b22686f73744e616d65223a226d6c633039227d`
- `authority` / `remoteAuthority`: `ssh-remote+7b22686f73744e616d65223a226d6c633039227d`
- hex → `{"hostName":"mlc09"}`

## What the bind script does

1. Load OLD/NEW `workspace.json`; require identical `ssh-remote%2B<hex>`
2. `UPDATE composerHeaders SET workspaceId=<NEW> WHERE workspaceId=<OLD>`
3. Patch `value` JSON paths/ids; set `uri.authority` to literal `+`, `external` to `%2B`
4. Backup under `Desktop\cursor_composerHeaders_table_backup_<timestamp>\`

## Out of scope

Remote agent-transcripts merge; conda / settings path rewrites.
