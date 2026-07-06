# Cursor Personal Skills

This repository syncs personal Cursor Skills and user-level Rules. The layout matches Cursor’s default conventions.

## Layout

- `*/SKILL.md` — main definition file for each skill
- Each subdirectory (except `rules/`) is one independent skill
- `rules/*.mdc` — user rules tracked in git; safely deployed to `~/.cursor/rules/` on pull
- `rules/.baseline/*.mdc` — snapshot of last successful deploy (detects live edits)

```
~/.cursor/
├── skills/          # this git repo
│   ├── rules/       # .mdc files (source of truth for sync)
│   └── <skill>/SKILL.md
└── rules/           # live path Cursor loads (synced from skills/rules/)
```

## Local setup

Place the repository at:

- `~/.cursor/skills/`

After clone or pull, use **更新skill** in Cursor chat for safe deploy (or copy only new files manually). Deploy will not overwrite `~/.cursor/rules/` when live was edited since the last deploy.

Cursor discovers skills under `~/.cursor/skills/` and rules under `~/.cursor/rules/` automatically.

## Cross-machine sync

On any machine, pull the latest skills and rules:

```bash
# In Cursor chat: 更新skill / 同步skill
git -C ~/.cursor/skills pull --ff-only
# Agent runs safe deploy per skill-sync (not blind cp)
```

After editing skills or rules locally, commit and push:

```bash
cp -f ~/.cursor/rules/*.mdc ~/.cursor/skills/rules/   # if you edited live rules
git -C ~/.cursor/skills add .
git -C ~/.cursor/skills commit -m "update skills and rules"
git -C ~/.cursor/skills push
```

## Agent commands (`skill-sync`)

In a Cursor chat you can say:

| Command | Action |
|---------|--------|
| **更新skill** / **pull skill** | Pull from GitHub; safe deploy `skills/rules/` → `~/.cursor/rules/` |
| **提交skill** / **commit skill** | Diff rules, collect live → repo if needed; commit and push |
| **检查rule** / **check rules** | Diff repo vs live vs baseline (no git) |
| **强制部署rule** / **force deploy rules** | Overwrite live from repo after you merged or accept repo version |

The `skill-sync` skill guides the agent. Live rules edited since last deploy are not overwritten silently; use diff, merge, then **提交skill** or **强制部署rule**.

## Notes

- Do not mix in content from the built-in directory `~/.cursor/skills-cursor/`
- Deploy does not remove extra `.mdc` files that exist only under `~/.cursor/rules/`
- Baseline duplicates each rule under `rules/.baseline/` to detect local edits (x2 storage tradeoff)
