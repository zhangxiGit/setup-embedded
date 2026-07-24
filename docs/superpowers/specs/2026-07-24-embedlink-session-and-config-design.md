# EmbedLink 会话提示与配置补全设计

## 背景

当前 `setup-embedded` 只在首次 UART 操作前执行 EmbedLink MCP capability preflight。若 MCP Tool 未暴露，skill 会停止并报告，但没有先引导用户启动 EmbedLink，也没有区分 Claude Code 与 Codex 的会话加载行为。

统一配置 `.embedded/embedded-config.md` 当前只有 `## Debug` UART 参数，没有记录 EmbedLink MCP service 的状态检查地址和 MCP endpoint，导致新生成或迁移后的配置缺少恢复调试所需的信息。

## 目标

1. 仅在 debug、hardware test 或 full loop 需要 EmbedLink 时执行 runtime-aware prerequisite gate。
2. 始终先检测当前 runtime 是否已暴露所需 EmbedLink MCP Tool；检测到时不提示重启会话。
3. 未检测到时提示用户启动 EmbedLink，并按 Claude Code / Codex 分支给出会话操作建议。
4. 新生成或迁移的 `.embedded/embedded-config.md` 必须包含固定 `## EmbedLink` service metadata。
5. 保持 MCP-only 边界：Agent 不自行启动 EmbedLink、不直接请求 HTTP endpoint、不使用本地串口 fallback。

## 非目标

- 不自动启动、停止或重启 EmbedLink。
- 不自动修改 Claude Code 或 Codex 的 MCP 全局配置。
- 不通过 PowerShell、Python、`curl`、HTTP client 或直接 COM access 验证 EmbedLink。
- 不改变 build-only 或 flash-only 工作流。
- 不新增配置生成脚本；继续由 skill 的统一配置 contract 指导生成和迁移。

## Runtime prerequisite gate

当请求被分类为 debug、hardware test 或 full loop 时，在首次 UART operation 前按以下顺序执行：

1. 检查当前 runtime 暴露的 tool inventory，判断所需 EmbedLink MCP Tool 是否存在。
2. Tool 已暴露：执行一次无副作用 capability preflight；不提示启动 EmbedLink 或新会话。
3. Tool 未暴露：停止当前 UART 阶段，提示用户先启动 EmbedLink，然后执行 runtime 分支。

### Claude Code 分支

Claude Code 当前会话不热加载新出现的 MCP service。Tool 未暴露时，明确告知用户：

1. 启动 EmbedLink。
2. 新建 Claude Code 会话。
3. 在新会话中重新发起 debug、hardware test 或 full loop 请求。

当前会话不得继续 UART debugging，也不得自动重试 MCP 调用。

### Codex 分支

Codex 的会话内 MCP 热加载能力不能作为固定前提。Tool 未暴露时：

1. 提示用户启动 EmbedLink。
2. 用户明确确认 EmbedLink 已启动后，在当前任务中重新检查一次 tool inventory。
3. 若 Tool 出现，执行 capability preflight 并继续。
4. 若仍未出现，提示用户新建 Codex 任务后重试，并停止当前 UART 阶段。

用户动作后的单次 tool inventory recheck 不是 MCP call retry；不得重复循环检查。

## 失败报告

Tool 未暴露或 capability preflight 失败时，继续使用固定六字段：

```text
阶段: <capability preflight | tool discovery>
MCP Tool: <runtime 实际 tool name；未暴露则写“未暴露”>
错误: <原始错误摘要>
已完成: <例如 build/flash 状态；无则写“无”>
未验证: <尚未取得 log evidence 的硬件行为>
用户操作建议: <按 Claude Code / Codex 分支填写启动与会话建议>
```

报告不能提供 shell、HTTP、serial CLI 或直接 COM fallback。

## 统一配置 contract

在现有 `## Debug` 后固定增加：

```markdown
## EmbedLink
- 状态检查: http://127.0.0.1:3000/health
- MCP端点: http://127.0.0.1:3000/mcp
```

字段语义：

- `状态检查` 和 `MCP端点` 是配置与人工排障信息，不授权 Agent 直接访问 HTTP endpoint。
- 实际可调用能力仍以当前 runtime 暴露的 MCP Tool name、description 和 input schema 为准。
- `connection_id` 仍是 runtime state，不写入文件。

新建统一配置时必须写入该 section。迁移 legacy `.Codex/embedded-config.md` 或 `.claude/embedded-config.md` 时，在用户确认后写入该 section，同时保留旧文件并丢弃 `rcw-tool` 专属字段。已有统一配置缺少该 section 时，只在需要 EmbedLink 的工作流中将其标记为配置不完整，并在用户确认后补入。

## 文件变更范围

- `SKILL.md`：加入 prerequisite gate、runtime 分支和完整配置模板。
- `references/embedlink-mcp.md`：定义 tool inventory 检测、Claude Code / Codex 分支、固定报告字段和禁止项。
- `README.md`：说明启动与新会话提示，以及统一配置中的 MCP service metadata。
- `tests/skill-scenarios.md`：加入 MCP 已存在、Claude Code 缺失、Codex 缺失和配置生成场景。
- `tests/forward-results.md`：记录新的 fresh-context 行为样本与 verdict。

不修改 firmware discovery、image guard、Keil/J-Link scripts 或 fixtures。

## 测试设计

### Static contract

验证 `SKILL.md` 与 reference 包含：

- 先检查 tool inventory。
- Tool 已暴露时不提示新会话。
- Claude Code 未暴露时提示启动 EmbedLink 和新会话。
- Codex 未暴露时只允许用户启动后的单次 tool inventory recheck，仍缺失才提示新任务。
- 统一配置模板含精确的 `## EmbedLink`、`状态检查`、`MCP端点` 和两个 URL。
- 不出现可执行 HTTP health check、本地串口或自动启动 EmbedLink 命令。

### Skill behavior forward tests

对每个行为使用 fresh context，至少运行五次完整 skill variant：

1. MCP Tool 已暴露：5/5 继续 preflight，0/5 提示重启。
2. Claude Code 未暴露：5/5 提示启动 EmbedLink、新建 Claude Code 会话并停止。
3. Codex 未暴露：5/5 提示启动；仅在用户确认后重新检查一次，仍缺失才提示新任务。
4. 生成或迁移配置：5/5 输出精确 `## EmbedLink` section。

先使用当前 skill 运行 no-new-guidance control，确认至少一个目标行为失败；再实施最小 guidance 并运行完整 variants。若 variant 暴露新 loophole，只针对原始失败形式修改 wording。

## 成功标准

- 四类行为测试均 5/5 PASS。
- 原有 A/B/C safety scenarios 不回归。
- `tests/run-tests.ps1 -Case all`、official `quick_validate.py` 与 `git diff --check` 全部通过。
- 没有 live EmbedLink MCP Tool 时，只验证提示与 contract，不声称完成 UART hardware verification。
