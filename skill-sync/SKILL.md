---
name: skill-sync
description: Sync personal Cursor skills and user rules between ~/.cursor/skills (GitHub Zantares/skills) and live paths. Pull when the user says "更新skill" or "pull skill" (also 同步skill, 拉取skill). Commit and push when the user says "提交skill" or "commit skill" (also 推送skill, 推送skill到github). Rules sync between ~/.cursor/skills/rules/ and ~/.cursor/rules/. On conflicts, explain options to the user and never auto-merge.
---

# Skill Sync

Synchronize the personal skills directory with its Git remote. The directory is a Git repository at `~/.cursor/skills/`.

Default remote (if `origin` is unset): `git@github.com:Zantares/skills.git`

## Paths

| Role | Path |
|------|------|
| Git repo (skills + rules source of truth for sync) | `~/.cursor/skills/` |
| Skills live | `~/.cursor/skills/*/SKILL.md` (same tree) |
| Rules in repo | `~/.cursor/skills/rules/*.mdc` |
| Rules live (Cursor loads these) | `~/.cursor/rules/*.mdc` |

Sibling layout:

```
~/.cursor/
├── skills/          # git repo
│   ├── rules/       # tracked .mdc files
│   └── */SKILL.md
└── rules/           # live Cursor user rules (not git root)
```

## Trigger Commands

| User says | Action |
|-----------|--------|
| **更新skill** / **pull skill** | Pull remote → repo, then deploy rules to `~/.cursor/rules/` |
| **提交skill** / **commit skill** | Collect rules from `~/.cursor/rules/` into repo, commit + push |
| 同步skill / 拉取skill | Same as 更新skill / pull skill |
| 推送skill / 推送skill到github | Same as 提交skill / commit skill |
| **检查rule** / **check rules** | Diff `~/.cursor/skills/rules/` vs `~/.cursor/rules/` only; no git |

Apply this skill only when the user explicitly uses one of these phrases (or an obvious synonym). Do not run sync on unrelated requests.

## Preconditions

Before any git command, verify:

1. `~/.cursor/skills/` exists and is a git repository (`git -C ~/.cursor/skills rev-parse --git-dir`).
2. Remote `origin` is configured; if missing, set it to `git@github.com:Zantares/skills.git` only after telling the user.
3. SSH or HTTPS auth works for push/pull (user has linked GitHub / keys).

If any precondition fails, report what is missing and stop. Do not guess credentials.

## Rules sync helpers

Use these shell steps (create directories if missing):

### Check rules (no copy)

```bash
REPO_RULES=~/.cursor/skills/rules
LIVE_RULES=~/.cursor/rules
mkdir -p "$REPO_RULES" "$LIVE_RULES"
diff -rq "$REPO_RULES" "$LIVE_RULES" || true
```

Report: files only in repo, only in live, or content differences. If identical, say so.

### Deploy rules: repo → live (after pull)

```bash
REPO_RULES=~/.cursor/skills/rules
LIVE_RULES=~/.cursor/rules
mkdir -p "$LIVE_RULES"
if [ -d "$REPO_RULES" ] && compgen -G "$REPO_RULES/*.mdc" > /dev/null; then
  cp -f "$REPO_RULES"/*.mdc "$LIVE_RULES/"
fi
```

Does not delete extra `.mdc` files that exist only under `~/.cursor/rules/`; mention orphans if present.

### Collect rules: live → repo (before commit)

```bash
REPO_RULES=~/.cursor/skills/rules
LIVE_RULES=~/.cursor/rules
mkdir -p "$REPO_RULES"
if [ -d "$LIVE_RULES" ] && compgen -G "$LIVE_RULES/*.mdc" > /dev/null; then
  cp -f "$LIVE_RULES"/*.mdc "$REPO_RULES/"
fi
```

If **check rules** shows repo and live diverge before commit, run check first, summarize diff, then collect live → repo unless the user says to keep repo version and deploy repo → live instead.

## Mode A — 更新skill / pull skill (pull)

Run in order:

```bash
git -C ~/.cursor/skills status --short --branch
git -C ~/.cursor/skills fetch origin
git -C ~/.cursor/skills pull --ff-only origin main
```

Then deploy rules (repo → `~/.cursor/rules/`).

Use `--ff-only` so a divergent history does not create a merge commit automatically.

**On success:** Summarize git changes and which `.mdc` files were copied to `~/.cursor/rules/`. Cursor picks up skills and rules on the next agent turn.

**On failure — stop and discuss with the user. Do NOT:**

- `git merge`, `git rebase`, or `git pull` without `--ff-only`
- Resolve conflicts by editing files
- Stash, reset, or force-push unless the user explicitly asks after you explain options

Typical failure cases to explain:

| Situation | What to tell the user |
|-----------|------------------------|
| Local uncommitted changes block pull | Commit or stash first; offer 提交skill / commit skill if they want to keep local work |
| Non-fast-forward (local and remote diverged) | Show `git log --oneline -3` for both sides; ask whether to commit local first, reset to remote, or merge manually themselves |
| Merge conflicts after accidental non-ff pull | Show `git status`; ask them to resolve in editor or choose abort (`git merge --abort` / `git rebase --abort`) |
| Auth / network errors | Check SSH key, `git remote -v`, GitHub access |

## Mode B — 提交skill / commit skill (commit + push)

1. **Check rules** (diff repo vs live).
2. If diverged, tell the user and default to **collect rules** (live → repo) unless they want the opposite direction.
3. Inspect changes:

```bash
git -C ~/.cursor/skills status --short
git -C ~/.cursor/skills diff
```

4. Stage all changes under the repo (respect `.gitignore`). Include `rules/*.mdc`. Do not add `~/.cursor/skills-cursor/` or paths outside this repo.

5. If there is nothing to commit, say so and stop (optionally offer 更新skill / pull skill if they expected remote changes).

6. Commit with a short message describing skill/rule changes. Use HEREDOC for the message if needed.

7. Push:

```bash
git -C ~/.cursor/skills push origin main
```

**On success:** Report commit hash, branch, remote URL, and whether rules were collected from live.

**On failure — stop and discuss. Do NOT:**

- Force-push (`git push --force`) unless the user explicitly requests it after understanding risk
- Auto-merge remote changes; if push is rejected (non-fast-forward), explain that 更新skill / pull skill may be needed first and ask how to proceed

| Situation | What to tell the user |
|-----------|------------------------|
| Push rejected (remote ahead) | Run 更新skill / pull skill first, or inspect divergence together |
| Nothing to commit | Working tree clean |
| Auth failure | Fix SSH / GitHub login |

## Mode C — 检查rule / check rules

1. Run **Check rules** only (no git, no copy).
2. Report differences or confirm both sides match.
3. If the user wants to reconcile, ask direction: **deploy** (repo → live) or **collect** (live → repo), then run that helper once.

## Output Format

After any mode, use a brief report:

- **Action:** 更新skill / pull skill / 提交skill / commit skill / 检查rule
- **Result:** success / blocked
- **Details:** commit range, skills/rules files touched, diff summary, or error message
- **Next step:** only if blocked or user may want another command

## Safety Rules

- Personal skills live only in `~/.cursor/skills/`. Never sync or commit `~/.cursor/skills-cursor/`.
- Rules source in git: `~/.cursor/skills/rules/`. Live load path: `~/.cursor/rules/`.
- Never commit secrets (tokens, `.env`, credentials) if they appear under the skills tree.
- Conflict resolution is always a human decision; present options, do not execute merge/rebase without explicit user instruction.
- Do not delete files in `~/.cursor/rules/` during deploy; only overwrite matching names from repo.
