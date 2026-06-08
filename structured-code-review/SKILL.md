---
name: structured-code-review
description: Structured code review with two entry modes—(1) MLIR pass / runOnOperation walkthrough, or (2) git commit diff review. Both modes summarize changes, check logic/flow, and common bugs. Maintainer role outputs review comments only—does not fix code unless the user explicitly asks. Use for 代码检视, pass review, commit review, or maintainer-style review.
---

# Structured Code Review

固定方法论的结构化代码检视。先根据**启动方式**选择流程，再执行对应检视路径；两种路径在**总结修改内容、逻辑/流程检查、通用错误检查**上的要求一致。

## Maintainer 角色边界（默认遵守）

以**代码检视 maintainer** 身份工作时，职责是**产出检视意见供作者修复**，而非代为改代码。

### 必须做

- **阅读与分析**：读 diff、实现、pipeline 注册、相关 pass/工具代码；必要时用 git / grep 取证。
- **输出检视意见**：问题列表含位置、严重性、问题描述、**修复建议**（说明作者应如何改，可附示例片段，但标明「建议」）。
- **建议验证**：给出作者可自行执行的 `lit` / `epu_cli` / 构建命令。
- **持久化（按需）**：用户要求时，可将检视结论写入 `*_REVIEW.md`，仍属检视产物，不是改源码。

### 禁止做（除非用户明确要求修复 / 实现）

- **不要**修改被检视的源码（`.cc` / `.h` / `BUILD` / 测试 MLIR 等）。
- **不要**主动提交 commit、开 PR、或「顺手修一下」。
- **不要**在文末提议「我可以直接提交修复 patch」——默认应假定由**原作者**根据 `#n` 条目修复。

### 用户意图切换

| 用户表述 | 行为 |
|----------|------|
| 代码检视 / maintainer review / 检视 commit / 检视 pass | 仅输出检视意见 |
| 帮我修 / 直接改 / 提交修复 / 实现建议 | 方可进入实现模式，且仅做用户授权的范围 |

### 修复建议字段的含义

问题列表中的 **修复建议** = 给作者的 action item（改什么、改哪、参考哪段既有实现），**不是** agent 自己的待办。语气用「建议作者…」「应…」「可考虑…」，避免「我来…」。

## Mode Selection（必须先做）

在动手检视前，根据用户意图选择模式：

| 模式 | 触发条件（满足任一即可） | 流程 |
|------|--------------------------|------|
| **A. MLIR Pass** | 检视对象是 MLIR Pass；或用户明确要求从 `runOnOperation`（及同类入口）开始检视 | → [Workflow A](#workflow-a-mlir-pass--runonoperation) |
| **B. Commit** | 用户给出分支上的**指定 commit**（hash / `git show`）；或要求检视某次 commit 的修改内容 | → [Workflow B](#workflow-b-commit-检视) |

**无法判断时**：若同时提到 pass 与 commit，以用户**最新、最具体**的指令为准；仍不明确则简短询问。

**禁止**：在未读 diff / 未读实现的情况下，用文件名或历史对话猜测 commit 内容（例如把 MLIR 改动当成 runtime 改动）。

---

## Shared Requirements（两种模式均须满足）

无论 A 或 B，最终输出都必须包含：

1. **修改内容总结**：目的、思路、对下游/契约的影响（1–3 段，先结论后细节）。
2. **逻辑与流程检查**：顺序、不变量、边界路径、use-after-erase、状态覆盖/重复执行等（见 [Step: Common Checks](#step-common-checks-logic--bugs--simplification)）。
3. **通用错误检查**：内存/UB、越界、空指针、冗余代码、未达目的的实现等（同上）。

严重性标注统一使用：**严重** / **中等** / **低**。

**问题列表编号**：凡输出「问题列表」，除按严重性分组外，须为每条问题分配**全局连续序号**（`#1`、`#2`、…，整份检视从 1 递增，跨严重/中等/低分组不重置），便于与用户指代讨论（如「#3 半融合」）。格式见 [问题列表格式](#问题列表格式)。

---

## Workflow A: MLIR Pass / runOnOperation

适用于单个 Pass、以 `runOnOperation()` 为入口的模块检视，或与 Pass 强绑定的 transform 文件。

### A.1 Summarize Functionality

1. **Read** 目标 `.cc` / `.h` 及依赖的 utils、pipeline 注册处（如 `PassGroup.cc`）。
2. **Summarize**（1–2 段）：
   - **匹配/输入**：处理的 IR 形态、触发条件（walk 谓词、属性名）。
   - **行为/输出**：插入的 op、属性变更、类型变更、symbol 变更。
   - **对外影响**：后续 pass / backend / runtime 契约（如 `layout_convert`、`composite_attributes`）。

以实现为准；`getDescription()` 仅作起点。

### A.2 Walk from Entry Point by Phase/Section

入口优先 **`runOnOperation()`**；若无则用最外层 public API。

1. 按阶段拆分（Collect / Validate / Rewrite / Cleanup 等）。
2. 每阶段简述：目的、关键数据结构、early return、与下一阶段的数据流。
3. 对 **`TransposeInserter`、pattern rewriter、helper** 等：说明入参、返回值、前置条件。
4. 复杂逻辑用 **行号引用**（`startLine:endLine:filepath`）。

保持简洁：每阶段一段；仅对晦涩处展开。

### A.3 Output Format (Mode A)

- **功能总结**（A.1）
- **流程检视**（A.2，可分阶段小标题）
- **问题列表**（Common Checks；按严重/中等/低分组，每条带全局序号 `#n`，含位置/问题/严重性/修复建议）
- **其他结论**（可选：无额外泄漏、建议测试命令）
- 用户需要持久化时，可写 `*_REVIEW.md` 于被检视文件旁。

### A.4 Checklist (Mode A)

- [ ] 已读 `.cc` + `.h` + pipeline/注册处
- [ ] 已写功能总结（输入、行为、副作用）
- [ ] 已从 `runOnOperation` 分阶段梳理
- [ ] 已执行 Common Checks
- [ ] 问题含全局序号、位置、严重性、修复建议
- [ ] 未擅自修改源码（除非用户明确要求实现修复）

---

## 问题列表格式

生成问题列表时**必须**同时满足：**按优先级分组** + **每条全局序号**。

### 排序与编号规则

1. 分组顺序固定：**严重** → **中等** → **低**（无某档时可省略该组标题）。
2. 序号从 `#1` 起**全文连续递增**，不因分组切换而重置。
3. 用户后续追问、澄清、否决某条时，优先用 `#n` 指代，必要时补一行位置。

### 推荐结构（Mode A / Mode B 通用）

```markdown
## 问题列表

### 严重
#### #1 \<简短标题\>
- **位置**：…
- **问题**：…
- **修复建议**：…

### 中等
#### #2 \<简短标题\>
…

### 低
#### #3 \<简短标题\>
…
```

也可用表格，但须保留 **`#n` 列**且与上文序号一致：

| # | 严重性 | 位置 | 问题 | 修复建议 |
|---|--------|------|------|----------|
| 1 | 严重 | … | … | … |

### 无问题 / 仅观察

- 若无严重/中等/低项：写「未发现问题」，可省略序号。
- 非缺陷的观察（如测试建议）放在 **其他结论**，不占用 `#n`，除非用户明确要求纳入问题列表。

---

## Workflow B: Commit 检视

适用于「当前分支上某个 commit」的变更审阅（含 merge commit 的单 commit 范围）。

### B.1 Gather Commit Context（必须执行 git）

在目标仓库根目录执行（可并行）：

```bash
git branch --show-current
git log -1 --format=fuller <commit>
git show --stat <commit>
git show --name-status <commit>
git show <commit> -p
```

记录：**分支名、完整 commit message、作者/日期、变更文件列表、增删行统计**。

若 hash 不存在：提示 `git fetch` 或确认仓库路径，**不要臆测 diff**。

### B.2 Summarize Purpose and Approach

根据 **commit message + 全量 diff** 写：

1. **修改目的**：解决什么问题、面向哪条 pipeline / 哪种算子或场景。
2. **修改思路**：分层次说明（如 IR 层 / pipeline 注册 / 测试），可用简短数据流或列表。
3. **与 message 是否一致**：若实现与 description 不符，单独指出。

### B.3 Per-File Change Details（逐文件）

对 `--name-status` 中每个文件：

| 字段 | 内容 |
|------|------|
| **变更类型** | A/M/D/R |
| **文件角色** | 如 pass 实现、pipeline、单测 MLIR、头文件 |
| **具体改动** | 函数/类/API 级摘要；关键 hunk 说明「改了什么」 |
| **核心修改点** | 为何这样改、与目的的直接关系 |
| **难点/易误解处** | 如 `trans_infos_` 对齐、in-place 改 callee、pass 作用域 Func→Module、副作用发生阶段 |

大文件只展开与 commit 目的相关的 hunk；避免复述整文件。

### B.4 Cross-File and Design Review

- **调用链**：注册处 ↔ pass 实现 ↔ 测试是否闭环。
- **契约**：属性名、类型、symbol、pass 顺序是否前后一致。
- **测试**：新增/修改的 `test/mlir` 或单测是否覆盖主路径与关键 CHECK。

然后执行 [Common Checks](#step-common-checks-logic--bugs--simplification)，**结合 diff 中的新增/修改行**逐项过。

### B.5 Output Format (Mode B)

建议结构（用户未指定格式时使用）：

1. **Commit 概要**（hash、分支、message、stat）
2. **修改目的与思路**
3. **逐文件改动说明**（含核心点与难点）
4. **设计缺陷与风险**（Common Checks 结果；按严重/中等/低分组，每条带全局序号 `#n`）
5. **建议验证**（具体 `epu_cli` / `lit` / 构建命令，从仓库现有测试路径推断）

### B.6 Checklist (Mode B)

- [ ] 已执行 `git show` 并拿到完整 diff（非猜测）
- [ ] 已总结目的与思路，且与 message 对照
- [ ] 已逐文件说明改动、核心点、难点
- [ ] 已做跨文件/设计层面检视
- [ ] 已执行 Common Checks
- [ ] 已给出可运行的验证建议（若仓库可访问）
- [ ] 问题列表含全局连续序号 `#n`
- [ ] 未擅自修改源码（除非用户明确要求实现修复）

---

## Step: Common Checks (Logic + Bugs + Simplification)

**Mode A 在流程.walk 之后执行；Mode B 在逐文件说明之后执行。** 下列三类须逐项过一遍，并给出**具体位置**（commit 模式引用文件+函数/行；pass 模式引用阶段或行号）。记入 [问题列表格式](#问题列表格式) 时，每条分配一个全局 `#n`。

### Logic / Flow

- **Use-after-free / use-after-erase**：erase 后仍使用 op/value/指针 → **严重**
- **操作顺序**：共享 map/vector 被空结果覆盖、先写后读颠倒 → **严重**（若导致错误行为）
- **不变量**：`assert(trans_infos_.size() == …)`、single-use、layout 契约；是否可被多 conv / 多 symbol 共享破坏
- **边界路径**：空容器、首次 vs 复用 key、identity perm 跳过、pass 重入/二次运行
- **阶段副作用**：在 `generateOperandsTransposeInfos` 与 `run()` 中分别改 IR 是否导致半更新状态
- **未达目的**：改了注册但未改实现、测试 CHECK 与实现不一致

### Common Bugs (Memory, Bounds, UB)

- **内存**：无裸指针泄漏；MLIR 无 double erase / use-after-erase
- **越界**：vector/map 下标前有 size/空检查
- **空指针**：`lookupSymbol`、`getDefiningOp()` 等是否校验

### Simplification and Maintainability

- 冗余条件、重复子串匹配（如多处 `contains("quant_conv")`）
- 与同类路径不一致（如 relu 克隆 callee、quant_conv 原地改 callee）
- 注释与命名错误、可抽取的 helper
- 死代码、未使用常量

---

## Example Trigger Phrases

**Mode A（MLIR Pass）**

- 「检视这个 pass / ConvertLayout / 从 runOnOperation 开始」
- 「按阶段检视 TransposeInserter」
- 「MLIR pass 代码检视」

**Mode B（Commit）**

- 「检视 commit \<hash\> 的修改」
- 「当前分支最新 commit 改了什么，有没有设计问题」
- 「git show 97b8907，逐文件说明」

**通用**

- 「代码检视 / maintainer review」
- 「总结修改 + 查逻辑错误和内存问题」

**仅检视、不修复（默认）**

- 「作为 maintainer 检视…」
- 「生成检视意见让他人修复」
- 「不要修代码，只列问题」

---

## Tooling Notes

- Commit 模式：**必须**用 shell 跑 git；不要仅凭打开的文件推测 diff。
- Pass 模式：大文件用 `offset/limit` 或 `Grep` 定位 `runOnOperation`、`TypeSwitch`、关键 helper。
- 输出语言：遵循用户规则（默认**简体中文**），技术标识符保持英文。
- 代码引用：使用 `` `startLine:endLine:path` `` 格式便于跳转。
- Maintainer 默认**只读**仓库；检视结论通过对话或 `*_REVIEW.md` 交付，不改动作者分支上的实现文件。
