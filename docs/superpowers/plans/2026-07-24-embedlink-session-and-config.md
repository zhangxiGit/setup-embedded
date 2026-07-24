# EmbedLink 会话提示与配置补全实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 `setup-embedded` 在需要 UART 时先检测 EmbedLink MCP 可用性，并把固定 MCP service metadata 写入统一配置 contract。

**Architecture:** 保持现有 Markdown-driven skill，不新增生成器或运行时依赖。`SKILL.md` 定义总流程和配置 contract，`references/embedlink-mcp.md` 定义 Claude Code / Codex 的 runtime 分支与 MCP-only 边界，README 和测试文档同步用户可见行为。

**Tech Stack:** Markdown、PowerShell 静态 contract tests、Codex/Claude Code skill behavior tests。

## Global Constraints

- debug、hardware test 与 full loop 的 UART 操作只允许通过 EmbedLink MCP Tool。
- build-only 与 flash-only 不检测 EmbedLink MCP。
- Agent 不启动或重启 EmbedLink，不调用 HTTP endpoint，不用 PowerShell、Python、serial CLI 或直接 COM access 代替 MCP。
- Claude Code 必须先检测 Tool；只有未暴露时才提示启动 EmbedLink 并新建会话。
- Codex 必须先检测 Tool；未暴露时提示启动，用户确认后只重新检查一次 tool inventory，仍缺失才提示新建任务。
- `.embedded/embedded-config.md` 必须包含固定 `## EmbedLink`、`状态检查` 与 `MCP端点` 信息。
- 按用户要求，所有修改和验证完成后只创建一次最终 commit。

---

### Task 1: 添加 EmbedLink 静态 contract 回归测试

**Files:**
- Modify: `tests/run-tests.ps1`

**Interfaces:**
- Consumes: 仓库根目录的 `SKILL.md`、`references/embedlink-mcp.md`、`README.md`。
- Produces: `-Case contract` 测试入口；`-Case all` 同时执行新 contract tests。

- [x] **Step 1: 编写失败测试**

在 `tests/run-tests.ps1` 中加入 `contract` case，并检查：

```powershell
Assert-Contains $skill '## EmbedLink' 'Unified config template must include EmbedLink section'
Assert-Contains $skill '- 状态检查: http://127.0.0.1:3000/health' 'EmbedLink health metadata missing'
Assert-Contains $skill '- MCP端点: http://127.0.0.1:3000/mcp' 'EmbedLink MCP endpoint missing'
Assert-Contains $reference 'Claude Code' 'Claude Code runtime branch missing'
Assert-Contains $reference 'Codex' 'Codex runtime branch missing'
Assert-Contains $reference '重新检查一次 tool inventory' 'Codex one-time inventory recheck missing'
```

同时断言 Tool 已暴露时不得提示新会话、Claude Code 未暴露时必须提示新会话，并断言 URL 仅作人工排障信息，不能作为 Agent 执行 HTTP 请求的依据。

- [x] **Step 2: 运行测试并确认 RED**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-tests.ps1 -Case contract
```

Expected: FAIL，首先报告 `Unified config template must include EmbedLink section` 或缺少 runtime branch。

### Task 2: 实现 prerequisite gate 与统一配置 contract

**Files:**
- Modify: `SKILL.md`
- Modify: `references/embedlink-mcp.md`
- Modify: `README.md`

**Interfaces:**
- Consumes: 当前 runtime tool inventory、用户对 EmbedLink 已启动的明确确认。
- Produces: Tool 已暴露、Claude Code Tool 缺失、Codex Tool 缺失三条确定分支；统一配置中的固定 service metadata。

- [x] **Step 1: 修改 `SKILL.md` 总流程**

把 UART slot 改为以下语义：

```text
先检查当前 runtime 的 tool inventory。Tool 已暴露时执行一次无副作用 capability preflight，不提示启动或新会话。Tool 未暴露时停止 UART 阶段，提示启动 EmbedLink，并按 Claude Code / Codex 分支处理。
```

在统一配置模板的 `## Debug` 后加入：

```markdown
## EmbedLink
- 状态检查: http://127.0.0.1:3000/health
- MCP端点: http://127.0.0.1:3000/mcp
```

明确新建、legacy migration 和需要 EmbedLink 时发现缺失 section 的补全规则。

- [x] **Step 2: 修改 `references/embedlink-mcp.md` runtime 分支**

写入以下确定行为：

```text
Claude Code: Tool 未暴露 → 启动 EmbedLink → 新建 Claude Code 会话 → 在新会话重试。
Codex: Tool 未暴露 → 启动 EmbedLink → 用户确认后重新检查一次 tool inventory → 出现则 preflight；仍缺失则新建 Codex 任务。
```

保留固定六字段失败报告，并让 `用户操作建议` 根据 runtime 分支填写。明确 Codex 的单次 inventory recheck 不是重复 MCP call；禁止循环检测。

- [x] **Step 3: 更新 `README.md`**

说明先检测后提示的共同规则、Claude Code 与 Codex 的差异，以及统一配置中的精确 `## EmbedLink` section。注明两个 URL 只供配置和人工排障使用。

- [x] **Step 4: 运行 contract tests 并确认 GREEN**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-tests.ps1 -Case contract
```

Expected: `Contract tests passed`。

### Task 3: 补全 skill behavior scenarios 与验证记录

**Files:**
- Modify: `tests/skill-scenarios.md`
- Modify: `tests/forward-results.md`

**Interfaces:**
- Consumes: 修改后的完整 skill variant。
- Produces: 四类场景的可复现 prompt、5 次 fresh-context 样本和 verdict。

- [x] **Step 1: 添加四类场景**

在 `tests/skill-scenarios.md` 增加：

```text
Scenario D: EmbedLink MCP Tool 已暴露，验证不提示启动或新会话。
Scenario E: Claude Code 中 Tool 未暴露，验证提示启动并新建 Claude Code 会话。
Scenario F: Codex 中 Tool 未暴露，验证用户确认启动后只 recheck 一次，仍缺失才新建任务。
Scenario G: 生成或迁移统一配置，验证精确输出 ## EmbedLink section。
```

每个场景写明 Pass/Fail 标准，禁止 HTTP/local serial fallback。

- [x] **Step 2: 运行 fresh-context behavior tests**

用五个 fresh context 分别运行完整 D/E/F/G 变体，记录原始 response。每类目标必须 5/5 PASS；Scenario D 必须 0/5 提示启动或新会话。

- [x] **Step 3: 更新 `tests/forward-results.md`**

逐项记录 prompt、五个样本、verdict 和限制：没有 live EmbedLink MCP Tool 时，不声称完成 UART hardware verification。

### Task 4: 全量验证、审查与统一提交

**Files:**
- Verify: 所有修改文件

**Interfaces:**
- Consumes: Tasks 1–3 的全部变更。
- Produces: 无格式错误、无回归、可追溯的单一 Git commit。

- [x] **Step 1: 运行全部回归测试**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-tests.ps1 -Case all
```

Expected: `All tests passed`。

- [x] **Step 2: 运行 skill validator**

Run:

```powershell
python C:\Users\zxx\.codex\skills\.system\skill-creator\scripts\quick_validate.py .
```

Expected: exit 0 且输出 validation success。

- [x] **Step 3: 检查内容与差异**

Run:

```powershell
rg -n "rcw-tool|pyserial|直接 COM|http://127.0.0.1:3000" SKILL.md README.md references tests
git diff --check
git status --short
```

Expected: `rcw-tool` 只出现在明确的 legacy 丢弃规则；串口词只出现在禁止项；URL 只出现在配置/说明/测试；`git diff --check` exit 0。

- [x] **Step 4: 统一提交**

Run:

```powershell
git add SKILL.md README.md references/embedlink-mcp.md tests/run-tests.ps1 tests/skill-scenarios.md tests/forward-results.md docs/superpowers/specs/2026-07-24-embedlink-session-and-config-design.md docs/superpowers/plans/2026-07-24-embedlink-session-and-config.md
git commit -m "feat: improve EmbedLink session guidance"
```

Expected: commit 成功，工作区 clean。
