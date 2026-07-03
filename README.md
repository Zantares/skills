# Cursor Personal Skills

This repository syncs personal Cursor Skills and user-level Rules. The layout matches Cursor’s default conventions.

## Layout

- `*/SKILL.md` — main definition file for each skill
- Each subdirectory (except `rules/`) is one independent skill
- `rules/*.mdc` — user rules tracked in git; deployed to `~/.cursor/rules/` on pull

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

Deploy rules once after clone or pull:

```bash
mkdir -p ~/.cursor/rules
cp -f ~/.cursor/skills/rules/*.mdc ~/.cursor/rules/
```

Cursor discovers skills under `~/.cursor/skills/` and rules under `~/.cursor/rules/` automatically.

## Cross-machine sync

On any machine, pull the latest skills and rules:

```bash
git -C ~/.cursor/skills pull
cp -f ~/.cursor/skills/rules/*.mdc ~/.cursor/rules/
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
| **更新skill** / **pull skill** | Pull from GitHub; copy `skills/rules/` → `~/.cursor/rules/` |
| **提交skill** / **commit skill** | Diff rules, copy `~/.cursor/rules/` → `skills/rules/` if needed; commit and push |
| **检查rule** / **check rules** | Diff repo rules vs live rules only (no git) |

The `skill-sync` skill guides the agent through these steps. On conflicts, the agent explains the situation and discusses options with you; it does not auto-merge.

## Notes

- Do not mix in content from the built-in directory `~/.cursor/skills-cursor/`
- Deploy does not remove extra `.mdc` files that exist only under `~/.cursor/rules/`
