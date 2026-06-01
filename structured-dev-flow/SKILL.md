---
name: structured-dev-flow
description: Drive coding tasks through a staged collaboration flow: brief requirement restatement, solution/options with risks, discussion, clarification, then implementation and verification. Use only when users explicitly ask for discuss-before-code collaboration (for example: "先讨论后实现", "先给方案和风险点", "确认后再改代码", "先澄清边界再开发"), especially in compiler, MLIR, pattern-matching, or rule-heavy changes.
---

# Structured Dev Flow

Use this workflow when the user prefers: "understand first, then build".

## Trigger Signals

Apply this skill when the user asks for any of these:
- "first discuss / do not code yet"
- "give plan and key points first"
- "clarify requirements before implementation"
- "after I confirm, then implement"
- compiler/pattern rules work that can easily over-match
- "先讨论后实现 / 先别改代码"
- "先给方案和风险点"
- "先澄清需求边界再开发"
- "等我确认后再动手实现"
- "按 简述需求->方案->讨论->澄清->实现 的流程来"

## Mis-trigger Guard

Do NOT apply this skill if the user clearly asks for immediate implementation, bug fix, or direct code edits without discuss-first intent.

Domain words alone (compiler/MLIR/pattern/rules) are NOT sufficient triggers.

If uncertain, ask one concise question: "你希望我先讨论方案，还是直接开始实现？"

## Workflow

### Phase 1 - Brief Requirement Restatement

- Restate the request in 1-3 sentences.
- Confirm boundaries (what to change, what not to change).
- Avoid implementation details in this phase.

Output shape:
- Goal
- Scope
- Non-goals

### Phase 2 - Proposal + Risks

- Provide a concrete feasible approach under current framework semantics.
- List key design points and trade-offs.
- Call out failure modes/regression risks (matching precision, behavior drift, rewrite safety).
- Do not edit files yet.

Output shape:
- Feasibility
- High-level approach
- Key design points
- Risks and mitigations

### Phase 3 - Discussion

- Answer user follow-up questions with examples and boundary cases.
- Keep language precise; avoid ambiguous terms.
- Compare "allowed" vs "not allowed" cases when matching semantics are involved.
- When discussion converges, transition to clarification lock instead of repeating the same comparisons.

### Phase 4 - Clarification Lock

Before coding, lock final semantics in explicit bullets:
- Allowed operations / traversal rules
- Stop conditions
- Rewrite conditions and rewrite target
- Rejection conditions

If any item is unclear, ask concise targeted questions.

Exit criteria for this phase (all required):
- Goal/scope/non-goals are explicit and non-conflicting.
- Allowed/rejected cases and stop conditions are complete enough to implement.
- Open ambiguities are either resolved or explicitly deferred.

### Phase 5 - Implementation

- Implement only after explicit confirmation from whitelist phrases, such as:
  - "可以开始改代码"
  - "按这个方案实现"
  - "开始实现"
  - "go ahead"
- Keep changes minimal and local first, then widen scope.
- Preserve existing behavior unless clarified otherwise.
- Add/adjust comments only where semantics are non-obvious.

### Phase 6 - Verification + Report

- Default to static verification and code inspection first.
- Do NOT auto-run tests/build by default.
- Ask the user whether they want minimal test verification or compile verification before running them.
- Report what changed, why, and what remains unverified.
- If tests/build are not requested, include suggested next validation commands as optional follow-ups.

## Communication Rules

- Keep progress updates short and frequent during exploration/editing.
- Lead with decisions and behavior changes, not tool logs.
- Use consistent terminology across the whole thread.
- Separate:
  - what was requested
  - what was implemented
  - what still needs confirmation

## Quality Checklist

Before final response, verify:
- Did we delay coding until user confirmation?
- Are semantics locked in explicit rules?
- Are rewrite side effects clearly stated?
- Are risky generalizations guarded by checks?
- Did we apply mis-trigger guard before entering this flow?
- Did we use confirmation whitelist before coding?
- Did verification at least include static checks/code inspection?

