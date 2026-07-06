---
name: skill-sync
description: Sync personal Cursor skills and user rules between ~/.cursor/skills (GitHub Zantares/skills) and live paths. Pull when the user says "更新skill" or "pull skill" (also 同步skill, 拉取skill). Commit and push when the user says "提交skill" or "commit skill" (also 推送skill, 推送skill到github). Rules deploy uses ~/.cursor/skills/rules/.baseline/ to avoid overwriting live edits. On conflicts, explain options and never auto-merge.
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
| Rules baseline (last deployed snapshot) | `~/.cursor/skills/rules/.baseline/*.mdc` |
| Rules live (Cursor loads these) | `~/.cursor/rules/*.mdc` |

Sibling layout:

```
~/.cursor/
├── skills/          # git repo
│   ├── rules/       # tracked .mdc files
│   │   └── .baseline/   # last-deployed snapshot (tracked; 1:1 with rules/*.mdc)
│   └── */SKILL.md
└── rules/           # live Cursor user rules (not git root)
```

**Baseline tradeoff:** each rule file has a duplicate under `.baseline/` (x2 storage in repo). This lets deploy detect whether live was edited since the last successful deploy.

## Trigger Commands

| User says | Action |
|-----------|--------|
| **更新skill** / **pull skill** | Pull remote → repo, then deploy rules to `~/.cursor/rules/` |
| **提交skill** / **commit skill** | Collect rules from `~/.cursor/rules/` into repo, commit + push |
| 同步skill / 拉取skill | Same as 更新skill / pull skill |
| 推送skill / 推送skill到github | Same as 提交skill / commit skill |
| **检查rule** / **check rules** | Diff repo rules vs live rules (and baseline if useful); no git |
| **强制部署rule** / **force deploy rules** | Deploy repo → live after user merged manually; refresh baseline |

Apply this skill only when the user explicitly uses one of these phrases (or an obvious synonym). Do not run sync on unrelated requests.

## Preconditions

Before any git command, verify:

1. `~/.cursor/skills/` exists and is a git repository (`git -C ~/.cursor/skills rev-parse --git-dir`).
2. Remote `origin` is configured; if missing, set it to `git@github.com:Zantares/skills.git` only after telling the user.
3. SSH or HTTPS auth works for push/pull (user has linked GitHub / keys).

If any precondition fails, report what is missing and stop. Do not guess credentials.

## Rules sync helpers

Path variables (create directories if missing):

```bash
REPO_RULES=~/.cursor/skills/rules
BASELINE_RULES=~/.cursor/skills/rules/.baseline
LIVE_RULES=~/.cursor/rules
```

### Check rules (no copy)

```bash
mkdir -p "$REPO_RULES" "$BASELINE_RULES" "$LIVE_RULES"
diff -rq "$REPO_RULES" "$LIVE_RULES" || true
diff -rq "$BASELINE_RULES" "$LIVE_RULES" || true
```

Report per file:

- only in repo / only in live / only in baseline
- repo vs live content differences
- live vs baseline (whether live was edited since last deploy)

If all three match for every tracked rule, say so.

### Safe deploy rules: repo → live (after pull)

**Never blind `cp -f` the whole tree.** For each `rules/*.mdc` in the repo, decide:

| Live file exists? | live vs repo | live vs baseline | Action |
|-------------------|--------------|------------------|--------|
| No | — | — | **Deploy** repo → live; set baseline = repo |
| Yes | same | — | **Skip**; ensure baseline = repo |
| Yes | different | no baseline yet | If live == repo: init baseline only. Else: **BLOCK** (manual merge) |
| Yes | different | live == baseline | **Deploy** (live unchanged since last deploy); baseline = repo |
| Yes | different | live != baseline | **BLOCK** (live edited locally); show diff, ask user to merge |

On **BLOCK**, run and show:

```bash
diff -u "$LIVE_RULES/<name>.mdc" "$REPO_RULES/<name>.mdc"
```

Tell the user to merge in the editor, then either **提交skill** (keep live edits) or **强制部署rule** (take repo version after they accept losing live edits).

**Bootstrap baseline** (first time or missing entries): for each repo `*.mdc`, if live is missing or live == repo, copy repo → baseline without touching live.

Does not delete extra `.mdc` files that exist only under `~/.cursor/rules/`; mention orphans if present.

### Force deploy rules (user confirmed)

Only when the user explicitly says **强制部署rule** / **force deploy rules**:

```bash
mkdir -p "$LIVE_RULES" "$BASELINE_RULES"
cp -f "$REPO_RULES"/*.mdc "$LIVE_RULES/"
cp -f "$REPO_RULES"/*.mdc "$BASELINE_RULES/"
```

Warn that this overwrites live and should be used only after manual review.

### Collect rules: live → repo (before commit)

```bash
mkdir -p "$REPO_RULES" "$BASELINE_RULES"
if [ -d "$LIVE_RULES" ] && compgen -G "$LIVE_RULES/*.mdc" > /dev/null; then
  cp -f "$LIVE_RULES"/*.mdc "$REPO_RULES/"
  cp -f "$LIVE_RULES"/*.mdc "$BASELINE_RULES/"
fi
```

After collect, repo and baseline should match live for collected files.

If **check rules** shows repo and live diverge before commit, run check first, summarize diff, then collect live → repo unless the user says to keep repo version and **force deploy** instead.

## Mode A — 更新skill / pull skill (pull)

Run in order:

```bash
git -C ~/.cursor/skills status --short --branch
git -C ~/.cursor/skills fetch origin
git -C ~/.cursor/skills pull --ff-only origin main
```

Then run **safe deploy rules** (repo → `~/.cursor/rules/`). If any file is **BLOCK**ed, stop deploy for that file and report; other safe files may still deploy.

Use `--ff-only` so a divergent history does not create a merge commit automatically.

**On success:** Summarize git changes; per rule file report deployed / skipped / blocked. Cursor picks up skills and rules on the next agent turn.

**On partial deploy:** List blocked files with `diff -u` output and next steps (merge → 提交skill, or 强制部署rule).

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

4. Stage all changes under the repo (respect `.gitignore`). Include `rules/*.mdc` and `rules/.baseline/*.mdc`. Do not add `~/.cursor/skills-cursor/` or paths outside this repo.

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
2. Report repo vs live and live vs baseline per file.
3. If the user wants to reconcile, ask direction: **safe deploy**, **collect** (live → repo), or **force deploy** (only after explicit confirmation).

## Mode D — 强制部署rule / force deploy rules

1. Confirm the user explicitly requested force (not part of normal pull).
2. Run **Force deploy rules**.
3. Report overwritten files and updated baseline.

## Output Format

After any mode, use a brief report:

- **Action:** 更新skill / pull skill / 提交skill / commit skill / 检查rule / 强制部署rule
- **Result:** success / blocked
- **Details:** commit range, skills/rules files touched, diff summary, or error message
- **Next step:** only if blocked or user may want another command

## Safety Rules

- Personal skills live only in `~/.cursor/skills/`. Never sync or commit `~/.cursor/skills-cursor/`.
- Rules source in git: `~/.cursor/skills/rules/`. Baseline: `rules/.baseline/`. Live load path: `~/.cursor/rules/`.
- Never commit secrets (tokens, `.env`, credentials) if they appear under the skills tree.
- Conflict resolution is always a human decision; present options, do not execute merge/rebase without explicit user instruction.
- Do not delete files in `~/.cursor/rules/` during deploy; only overwrite matching names when safe deploy or force deploy allows it.
- Never overwrite live rules silently when live differs from baseline (user edited since last deploy).
