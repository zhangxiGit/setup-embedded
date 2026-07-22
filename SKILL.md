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
2. **读取项目约束与配置**：读取当前 runtime 适用的 `AGENTS.md` 和/或 `CLAUDE.md`，再读取 `.embedded/embedded-config.md`。
3. **发现并确认候选**：缺少统一配置或配置不完整时，运行：

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\discover-embedded.ps1 -ProjectRoot <workspace-absolute-path>
   ```

   展示 JSON 中每个 `.uvprojx`、target、`role_hint`、`range_sources`、`layout_status`、`layout_conflicts`、`effective_range` 与 `artifact_path`。`layout_status=conflict` 或 `role_hint=unknown` 时 fail closed：展示冲突并停止，不得写入统一配置或继续 build/flash。自动发现只产生候选；让用户确认哪组是 boot、哪组是 app，以及对应 Flash layout，确认前不 build/flash。
4. **处理 legacy config**：发现 `.Codex/embedded-config.md` 或 `.claude/embedded-config.md` 时，先展示可迁移字段并取得用户确认。只迁移有效的 Keil、J-Link、project、Flash layout 与 UART 参数；丢弃 `rcw-tool` 专属字段。新建 `.embedded/embedded-config.md`，旧文件保持原样，不删除、不覆盖。
5. **绑定目标**：默认选择 app。artifact identity 的正向 contract 是且只能来自统一配置中的这一组：

   ```text
   Project = AppProject
   Target = AppTarget
   Artifact = AppArtifact
   ```

   build、freshness check、image guard 与 J-Link `loadfile` 必须沿用同一组绝对路径和 target。不得用全仓库或输出目录中修改时间最新的 HEX 替代 `AppArtifact`。
6. **执行 build（如适用）**：按 Keil reference 构建 exact project/target，并同时验证 process exit 0、日志含 `0 Error(s)`、绑定 artifact 晚于本次 build 开始时间。
7. **REQUIRED image guard（每次 flash 都适用）**：在创建 J-Link command file 或执行 `loadfile` 前，使用统一配置中的边界运行 `scripts/verify-firmware-image.ps1`。只有 process exit 0 且 JSON 为 `safe: true` 才能进入下一 slot；否则停止，不生成或提供绕过命令。
8. **Boot mode gate**：仅当用户明确要求烧录 bootloader 时才可选择 `BootProject` / `BootTarget` / `BootArtifact`。运行前再次展示 artifact 与 boot range，取得第二次明确确认，再以 `-Mode boot -BootFlashConfirmed` 执行 guard。缺少任一确认即停止。
9. **执行 J-Link flash（如适用）**：只对刚通过 guard 的 exact artifact 执行 Keil/J-Link reference 中的无 erase 流程。
10. **执行 UART 操作（如适用）**：debug、hardware test 或 full loop 在首次 UART 操作前只做一次无副作用 EmbedLink MCP capability preflight；其余操作遵循 EmbedLink reference。MCP 失败时，最终用户报告必须逐字、按顺序使用 `阶段`、`MCP Tool`、`错误`、`已完成`、`未验证`、`用户操作建议` 六个字段名；不得用同义字段替换。
11. **报告结果**：build、flash 与 hardware verification 分开报告。只有实际 EmbedLink MCP log evidence 能证明预期硬件行为时，才报告 hardware verification success。flash 已完成但 MCP 不可用时，报告“已烧录，但硬件行为尚未验证”。

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
```

配置值、discovery JSON、linker/scatter 信息或 image range 发生冲突时，展示冲突并请求用户修正或确认；不得自行选择一个来源继续 flash。

## 快速判定表

| 条件 | 结果 |
|---|---|
| app project/target/artifact 未精确绑定 | 停止 build/flash，完成 discovery 与确认 |
| build 三重验证任一失败 | 停止，不把 artifact 交给 guard |
| guard 非 exit 0 或 `safe` 非 `true` | 停止，不创建 J-Link command file |
| boot 未明确请求或缺少第二次确认 | 停止 boot flash |
| EmbedLink MCP Tool 缺失或报错 | 立即停止 UART debugging 并按固定字段报告 |
| 没有 MCP log evidence | 不报告 hardware verification success |

## 常见错误

- 把“app 目录里最新 HEX”当作目标：回到 `AppProject` / `AppTarget` / `AppArtifact` contract。
- build 成功后直接 `loadfile`：补上 REQUIRED image guard slot，并向用户展示 safe JSON。
- 用户催促时跳过确认：时间压力不改变 fail-closed gate。
- MCP 故障后改用本地串口：立即停止并使用 EmbedLink reference 的错误报告格式。
