# Cursor Personal Skills

这个仓库用于同步个人 Cursor Skills，目录与 Cursor 默认约定保持一致。

## 目录结构

- `*/SKILL.md`：每个 skill 的主定义文件
- 每个子目录代表一个独立 skill

## 在本机使用

将仓库内容放在：

- `~/.cursor/skills/`

Cursor 会自动发现该目录下的 skills。

## 跨机器同步

在任意机器上执行：

```bash
git -C ~/.cursor/skills pull
```

修改 skill 后提交并推送：

```bash
git -C ~/.cursor/skills add .
git -C ~/.cursor/skills commit -m "update skills"
git -C ~/.cursor/skills push
```

## Agent 口令（skill-sync）

在 Cursor 对话中可直接说：

| 口令 | 作用 |
|------|------|
| **更新skill** | 从 GitHub 拉取到本机 `~/.cursor/skills/` |
| **提交skill** | 将本机 skill 变更提交并推送到远程 |

由 `skill-sync` skill 指导 Agent 执行；若发生冲突，Agent 会说明情况并与你讨论，不会自动合并。

## 建议

- 不要把内置目录 `~/.cursor/skills-cursor/` 的内容混入本仓库
