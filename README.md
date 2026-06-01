# Cursor Personal Skills

This repository syncs personal Cursor Skills. The layout matches Cursor’s default conventions.

## Layout

- `*/SKILL.md` — main definition file for each skill
- Each subdirectory is one independent skill

## Local setup

Place the repository at:

- `~/.cursor/skills/`

Cursor discovers skills under that directory automatically.

## Cross-machine sync

On any machine, pull the latest skills:

```bash
git -C ~/.cursor/skills pull
```

After editing skills, commit and push:

```bash
git -C ~/.cursor/skills add .
git -C ~/.cursor/skills commit -m "update skills"
git -C ~/.cursor/skills push
```

## Agent commands (`skill-sync`)

In a Cursor chat you can say:

| Command | Action |
|---------|--------|
| **更新skill** / **pull skill** | Pull from GitHub into `~/.cursor/skills/` |
| **提交skill** / **commit skill** | Commit and push local skill changes to the remote |

The `skill-sync` skill guides the agent through these steps. On conflicts, the agent explains the situation and discusses options with you; it does not auto-merge.

## Notes

- Do not mix in content from the built-in directory `~/.cursor/skills-cursor/`
