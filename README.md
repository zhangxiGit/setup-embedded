# setup-embedded — Codex / Claude Code 嵌入式开发 Skill

`setup-embedded` 为 Codex 与 Claude Code 提供同一套 **Build → Flash → UART verification** 工作流。Codex 中使用 `$setup-embedded`，Claude Code 中使用 `/setup-embedded`。

## 当前支持范围

- OS：Windows
- Build：Keil MDK (`UV4.exe`)
- Flash：SEGGER J-Link (`JLink.exe`)
- Debug：仅通过 EmbedLink MCP 执行 UART list/connect/disconnect/send/query

当前版本不承诺 GCC、ST-Link、OpenOCD、USB HID 或 MQTT 的完整支持。Build 与 flash 使用本地 Keil/J-Link；UART debugging 不使用 PowerShell、Python、serial CLI 或其他 fallback。

## Flash safety

默认只构建和烧录 `.embedded/embedded-config.md` 明确绑定的 app project、target 与 artifact，不按修改时间选择 newest HEX。烧录 bootloader 必须由用户明确请求，并在执行前再次确认 boot artifact 与 address range。

任何 J-Link `loadfile` 之前都必须运行 `scripts/verify-firmware-image.ps1`。只有 process exit code 为 `0` 且 JSON 中 `safe: true` 时才允许继续；bootloader overlap、range conflict、erase boundary 未确认或 artifact identity 不确定时均 fail closed。

## 安装

克隆仓库后，把完整 skill 目录复制到对应 runtime：

```powershell
git clone https://github.com/zhangxiGit/setup-embedded.git

# Codex
Copy-Item -Recurse -LiteralPath .\setup-embedded -Destination "$env:USERPROFILE\.codex\skills\setup-embedded"

# Claude Code
Copy-Item -Recurse -LiteralPath .\setup-embedded -Destination "$env:USERPROFILE\.claude\skills\setup-embedded"
```

使用前需安装 Keil MDK 与 J-Link，并在当前 runtime 配置可用的 EmbedLink MCP server；EmbedLink 源码见 [embedlink_claude](https://gitee.com/zhangxi95/embedlink_claude)。两个 runtime 共用仓库内的 `SKILL.md`、scripts 和 references，不要只复制 `SKILL.md`。

## Unified config

Codex 与 Claude Code 共用项目根目录下的 `.embedded/embedded-config.md`。该文件绑定 exact `AppProject` / `AppTarget` / `AppArtifact`、boot project/artifact、Flash layout、J-Link 参数与 EmbedLink MCP UART 参数；`connection_id` 属于 runtime state，不写入配置。

如果项目只有 legacy `.Codex/embedded-config.md` 或 `.claude/embedded-config.md`，skill 会先展示可迁移字段并请求确认，再创建新的 `.embedded/embedded-config.md`。迁移保留旧文件，不删除、不覆盖；`rcw-tool` 专属 fields 不迁移。

## Validation limit

没有 live EmbedLink MCP runtime 时，只能验证 discovery、build/flash safety scripts、MCP contract 与 failure behavior。在没有实际 EmbedLink MCP log evidence 时，不能声称 hardware 或 UART verification 已成功；flash 已完成时应报告“已烧录，但硬件行为尚未验证”。

## License

MIT

## Author

zhangxiGit — 与 Claude Code 协作开发
