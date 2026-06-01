---
name: skill-sync
description: Sync personal Cursor skills between ~/.cursor/skills and GitHub (Zantares/skills). Use when the user says "更新skill" to pull remote into local, or "提交skill" to commit and push local changes. Also trigger on "同步skill", "拉取skill", "推送skill", "推送skill到github". On conflicts, explain options to the user and never auto-merge.
---

# Skill Sync

Synchronize the personal skills directory with its Git remote. The directory is a Git repository at `~/.cursor/skills/`.

Default remote (if `origin` is unset): `git@github.com:Zantares/skills.git`

## Trigger Commands

| User says | Action |
|-----------|--------|
| **更新skill** | Pull remote → local (`git pull`) |
| **提交skill** | Commit + push local → remote |
| 同步skill / 拉取skill | Same as 更新skill |
| 推送skill / 推送skill到github | Same as 提交skill |

Apply this skill only when the user explicitly uses one of these phrases (or an obvious synonym). Do not run sync on unrelated requests.

## Preconditions

Before any git command, verify:

1. `~/.cursor/skills/` exists and is a git repository (`git -C ~/.cursor/skills rev-parse --git-dir`).
2. Remote `origin` is configured; if missing, set it to `git@github.com:Zantares/skills.git` only after telling the user.
3. SSH or HTTPS auth works for push/pull (user has linked GitHub / keys).

If any precondition fails, report what is missing and stop. Do not guess credentials.

## Mode A — 更新skill (pull)

Run in order:

```bash
git -C ~/.cursor/skills status --short --branch
git -C ~/.cursor/skills fetch origin
git -C ~/.cursor/skills pull --ff-only origin main
```

Use `--ff-only` so a divergent history does not create a merge commit automatically.

**On success:** Summarize what changed (files updated, new commits). Cursor will pick up skills from `~/.cursor/skills/` on the next agent turn.

**On failure — stop and discuss with the user. Do NOT:**

- `git merge`, `git rebase`, or `git pull` without `--ff-only`
- Resolve conflicts by editing files
- Stash, reset, or force-push unless the user explicitly asks after you explain options

Typical failure cases to explain:

| Situation | What to tell the user |
|-----------|------------------------|
| Local uncommitted changes block pull | Commit or stash first; offer 提交skill if they want to keep local work |
| Non-fast-forward (local and remote diverged) | Show `git log --oneline -3` for both sides; ask whether to commit local first, reset to remote, or merge manually themselves |
| Merge conflicts after accidental non-ff pull | Show `git status`; ask them to resolve in editor or choose abort (`git merge --abort` / `git rebase --abort`) |
| Auth / network errors | Check SSH key, `git remote -v`, GitHub access |

## Mode B — 提交skill (commit + push)

1. Inspect changes:

```bash
git -C ~/.cursor/skills status --short
git -C ~/.cursor/skills diff
```

2. Stage all skill changes under the repo (respect `.gitignore`). Do not add `~/.cursor/skills-cursor/` or paths outside this repo.

3. If there is nothing to commit, say so and stop (optionally offer 更新skill if they expected remote changes).

4. Commit with a short message describing the skill changes (e.g. `Add skill-sync`, `Update structured-dev-flow`). Use HEREDOC for the message if needed.

5. Push:

```bash
git -C ~/.cursor/skills push origin main
```

**On success:** Report commit hash, branch, and remote URL.

**On failure — stop and discuss. Do NOT:**

- Force-push (`git push --force`) unless the user explicitly requests it after understanding risk
- Auto-merge remote changes; if push is rejected (non-fast-forward), explain that 更新skill may be needed first and ask how to proceed

| Situation | What to tell the user |
|-----------|------------------------|
| Push rejected (remote ahead) | Run 更新skill first, or inspect divergence together |
| Nothing to commit | Working tree clean |
| Auth failure | Fix SSH / GitHub login |

## Output Format

After either mode, use a brief report:

- **Action:** 更新skill / 提交skill
- **Result:** success / blocked
- **Details:** commit range, files touched, or error message
- **Next step:** only if blocked or user may want the other command

## Safety Rules

- Personal skills live only in `~/.cursor/skills/`. Never sync or commit `~/.cursor/skills-cursor/`.
- Never commit secrets (tokens, `.env`, credentials) if they appear under the skills tree.
- Conflict resolution is always a human decision; present options, do not execute merge/rebase without explicit user instruction.
