---
name: setup-embedded
description: Use when building, flashing, debugging, or hardware-testing Windows embedded firmware projects that use Keil MDK, J-Link, or EmbedLink MCP, especially repositories with separate bootloader and application projects.
---

# Windows 嵌入式开发闭环

## 核心原则

首版仅处理 Windows、Keil MDK、J-Link 与 EmbedLink MCP UART。默认目标是配置明确绑定的 application；任何 project role、Flash layout、erase boundary、artifact identity 或 image range 不确定时都 fail closed。

仅执行用户要求的阶段及其必要前置检查，不把 build 自动扩展为 flash，也不把 flash 自动扩展为 UART debugging。

## 资源路由

- build 或 flash：读取 [references/keil-jlink.md](references/keil-jlink.md)。
- debug、hardware test 或 full loop：读取 [references/embedlink-mcp.md](references/embedlink-mcp.md)。
- 缺少统一配置或需要重新发现工程：运行 `scripts/discover-embedded.ps1`。
- 每次调用 J-Link 前：运行 `scripts/verify-firmware-image.ps1`。

## REQUIRED ordered workflow

按以下顺序执行，不跳过适用的 slot：

1. **分类请求**：归类为 build、flash、debug、hardware test 或 full loop；不清楚时先确认范围。
2. **读取项目约束与配置**：读取当前 runtime 适用的 `AGENTS.md` 和/或 `CLAUDE.md`，再读取 `.embedded/embedded-config.md`。debug、hardware test 或 full loop 所用的统一配置缺少 `## EmbedLink` section 时，将配置标记为不完整，展示待补字段并取得用户确认后再补入；build-only 或 flash-only 不因此阻塞。
3. **发现并确认候选**：缺少统一配置或配置不完整时，运行：

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\discover-embedded.ps1 -ProjectRoot <workspace-absolute-path>
   ```

   展示 JSON 中每个 `.uvprojx`、target、`role_hint`、`range_sources`、`layout_status`、`layout_conflicts`、`effective_range` 与 `artifact_path`。`layout_status=conflict` 或 `role_hint=unknown` 时 fail closed：展示冲突并停止，不得写入统一配置或继续 build/flash。自动发现只产生候选；让用户确认哪组是 boot、哪组是 app，以及对应 Flash layout，确认前不 build/flash。
4. **处理 legacy config**：发现 `.Codex/embedded-config.md` 或 `.claude/embedded-config.md` 时，先展示可迁移字段并取得用户确认。只迁移有效的 Keil、J-Link、project、Flash layout 与 UART 参数，并补入固定 `## EmbedLink` service metadata；丢弃 `rcw-tool` 专属字段。新建 `.embedded/embedded-config.md`，旧文件保持原样，不删除、不覆盖。
5. **MCP 工作流门控（MCP workflow gate）**：仅当请求分类为 debug、hardware test 或 full loop 时执行，并且必须在绑定目标、build、flash 或 UART 前完成。先检查当前 runtime 暴露的 EmbedLink MCP tool inventory；Tool 未暴露时按 EmbedLink reference 的固定六字段报告停止整个请求，不执行 build/flash/UART。Tool 已暴露时只执行一次无副作用 capability preflight；preflight 失败同样停止整个请求。build-only / flash-only 跳过此门控；分类不清或无法确定是否涉及 MCP 时，先确认范围，不假设也不继续。
6. **绑定目标**：默认选择 app。artifact identity 的正向 contract 是且只能来自统一配置中的这一组：

   ```text
   Project = AppProject
   Target = AppTarget
   Artifact = AppArtifact
   ```

   build、freshness check、image guard 与 J-Link `loadfile` 必须沿用同一组绝对路径和 target。不得用全仓库或输出目录中修改时间最新的 HEX 替代 `AppArtifact`。
7. **执行 build（如适用）**：按 Keil reference 构建 exact project/target，并同时验证 process exit 0、日志含 `0 Error(s)`、绑定 artifact 晚于本次 build 开始时间。
8. **REQUIRED image guard（每次 flash 都适用）**：在创建 J-Link command file 或执行 `loadfile` 前，使用统一配置中的边界运行 `scripts/verify-firmware-image.ps1`。只有 process exit 0 且 JSON 为 `safe: true` 才能进入下一 slot；否则停止，不生成或提供绕过命令。
9. **Boot mode gate**：仅当用户明确要求烧录 bootloader 时才可选择 `BootProject` / `BootTarget` / `BootArtifact`。运行前再次展示 artifact 与 boot range，取得第二次明确确认，再以 `-Mode boot -BootFlashConfirmed` 执行 guard。缺少任一确认即停止。
10. **执行 J-Link flash（如适用）**：只对刚通过 guard 的 exact artifact 执行 Keil/J-Link reference 中的无 erase 流程。
11. **执行 UART 操作（如适用）**：debug、hardware test 或 full loop 只能复用本请求在第 5 步已成功完成的 MCP 工作流门控；不重新检查 tool inventory，也不执行第二次 capability preflight。`Runtime order: inspect tool inventory first.` `Tool available: no startup or new-session prompt.` 若第 5 步没有成功完成，停止整个请求，不执行 UART。后续 UART MCP 调用失败时，最终用户报告必须逐字、按顺序使用 `阶段`、`MCP Tool`、`错误`、`已完成`、`未验证`、`用户操作建议` 六个字段名；不得用同义字段替换。
12. **报告结果**：build、flash 与 hardware verification 分开报告。只有实际 EmbedLink MCP log evidence 能证明预期硬件行为时，才报告 hardware verification success。flash 已完成但 MCP 不可用时，报告“已烧录，但硬件行为尚未验证”。

## 统一配置 contract

Codex 与 Claude Code 共用 `.embedded/embedded-config.md`。地址使用十六进制；`connection_id` 是 runtime state，不写入文件。

```markdown
# Embedded 开发配置

## Build
- Tool: Keil MDK
- UV4Path: ...
- AppProject: ...
- AppTarget: ...
- AppArtifact: ...
- BootProject: ...
- BootTarget: ...
- BootArtifact: ...

## FlashLayout
- BootStart: 0x...
- BootEndExclusive: 0x...
- AppStart: 0x...
- AppEndExclusive: 0x...
- AppStartEraseBoundaryConfirmed: true

## Flash
- Tool: J-Link
- JLinkPath: ...
- Device: ...
- Interface: SWD
- SpeedKHz: 4000

## Debug
- Tool: EmbedLink MCP
- Transport: UART
- Port: ...
- BaudRate: ...
- DataBits: 8
- StopBits: one
- Parity: none
- FlowControl: none

## EmbedLink
- 状态检查: http://127.0.0.1:3000/health
- MCP端点: http://127.0.0.1:3000/mcp
```

`## EmbedLink` 中的 URL 只用于配置记录和人工排障，不授权 Agent 直接发起 HTTP 请求。实际能力始终以当前 runtime 暴露的 MCP Tool name、description 与 input schema 为准。新建统一配置和经用户确认的 legacy migration 必须包含该 section。

配置值、discovery JSON、linker/scatter 信息或 image range 发生冲突时，展示冲突并请求用户修正或确认；不得自行选择一个来源继续 flash。

## 快速判定表

| 条件 | 结果 |
|---|---|
| app project/target/artifact 未精确绑定 | 停止 build/flash，完成 discovery 与确认 |
| build 三重验证任一失败 | 停止，不把 artifact 交给 guard |
| guard 非 exit 0 或 `safe` 非 `true` | 停止，不创建 J-Link command file |
| boot 未明确请求或缺少第二次确认 | 停止 boot flash |
| 工作流涉及 EmbedLink MCP 且 MCP Tool 未暴露 | 停止整个工作流，不进入 build/flash/UART；按 runtime 分支报告 |
| 工作流涉及 EmbedLink MCP 且 capability preflight 报错 | 停止整个工作流，不进入 build/flash/UART；按固定字段报告 |
| build-only / flash-only 且 MCP 未暴露 | 不因此阻塞 |
| 没有 MCP log evidence | 不报告 hardware verification success |

## 常见错误

- 把“app 目录里最新 HEX”当作目标：回到 `AppProject` / `AppTarget` / `AppArtifact` contract。
- build 成功后直接 `loadfile`：补上 REQUIRED image guard slot，并向用户展示 safe JSON。
- 用户催促时跳过确认：时间压力不改变 fail-closed gate。
- 把 full loop 拆成独立阶段顺序执行，未先完成 MCP 工作流门控：回到第 5 步；MCP 未确认可用前不得 build/flash。
- MCP 未确认可用时先执行 build/flash：停止；先完成 MCP workflow gate，避免后续 UART 阶段无法收尾。
- MCP 故障后改用本地串口：立即停止并使用 EmbedLink reference 的错误报告格式。
