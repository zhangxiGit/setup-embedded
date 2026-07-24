# setup-embedded

中文 | [English](README_EN.md)

面向 Codex 与 Claude Code 的 Windows 嵌入式开发 Skill，提供安全、可审计的 **Build → Flash → UART verification** 工作流。

默认只处理配置明确绑定的 application firmware。烧录前会校验 artifact identity 与 Flash address range，避免 app image 覆盖 bootloader。UART 调试只允许通过 EmbedLink MCP 完成。

## 核心能力

- 精确构建 `.embedded/embedded-config.md` 绑定的 Keil project、target 与 artifact。
- 每次 J-Link flash 前检查 HEX/BIN 的实际地址范围。
- 默认禁止 bootloader flash；只有明确请求并二次确认后才允许执行。
- 禁止按修改时间选择 newest HEX，避免误烧录其他 project 的产物。
- 通过 EmbedLink MCP 执行 UART list、connect、send、query 与 disconnect。
- Codex 与 Claude Code 共用同一份 project config 和安全规则。

## 支持范围

| 项目 | 当前支持 |
|---|---|
| OS | Windows |
| Build | Keil MDK / `UV4.exe` |
| Flash | SEGGER J-Link / `JLink.exe` |
| Firmware | Intel HEX、BIN |
| Debug transport | EmbedLink MCP UART |
| Agent runtime | Codex、Claude Code |

GCC、ST-Link、OpenOCD、USB HID 与 MQTT 暂不属于完整支持范围。

## 前置条件

- 已安装 Keil MDK，并能定位 `UV4.exe`。
- 已安装 SEGGER J-Link，并能定位 `JLink.exe`。
- 需要 UART debugging、hardware test 或 full loop 时，安装并启动 [EmbedLink](https://gitee.com/zhangxi95/embedlink_claude)，同时在当前 Agent runtime 中配置其 MCP server。
- 仅执行 build 或 flash 时不需要启动 EmbedLink。

## 安装

### Codex

```powershell
git clone https://github.com/zhangxiGit/setup-embedded.git `
  "$env:USERPROFILE\.codex\skills\setup-embedded"
```

安装或更新后，建议新建 Codex 任务，以确保加载最新 Skill。

### Claude Code

```powershell
git clone https://github.com/zhangxiGit/setup-embedded.git `
  "$env:USERPROFILE\.claude\skills\setup-embedded"
```

安装或更新后，新建 Claude Code 会话。

已有安装可通过以下命令更新：

```powershell
git -C <setup-embedded-install-path> pull
```

## 使用

Codex：

```text
$setup-embedded 编译并安全烧录 app，然后通过 UART 验证启动日志。
```

Claude Code：

```text
/setup-embedded 编译并安全烧录 app，然后通过 UART 验证启动日志。
```

Skill 会先判断请求属于 build、flash、debug、hardware test 或 full loop，只执行用户要求的阶段及其必要检查。

## 工作流

### Build

1. 读取 `.embedded/embedded-config.md`。
2. 使用 exact `AppProject` 与 `AppTarget` 调用 Keil。
3. 同时验证 process exit code、`0 Error(s)` 与 bound artifact freshness。
4. 后续步骤始终沿用 exact `AppArtifact`。

### Flash

1. 每次调用 J-Link 前运行 `scripts/verify-firmware-image.ps1`。
2. 验证 image range 位于已确认的 application Flash range 内。
3. 只有 guard exit code 为 `0` 且 JSON 为 `safe: true` 才继续。
4. J-Link command 不使用 chip erase、mass erase 或 `erase`。

如果用户明确要求烧录 bootloader，Skill 会再次展示 boot artifact 与 address range，并要求第二次明确确认。

### UART verification

UART 操作只通过 EmbedLink MCP Tool 完成。Agent 不会使用 PowerShell、Python、`pyserial`、serial CLI、HTTP endpoint 或直接 COM access 作为 fallback。

没有实际 EmbedLink MCP log evidence 时，Skill 不会声称 hardware verification 已成功。即使 flash 已完成，也只会报告“已烧录，但硬件行为尚未验证”。

## EmbedLink 检测与会话行为

需要 UART 时，Skill 首先检查当前 runtime 是否已经暴露 EmbedLink MCP Tool：

- Tool 已暴露：执行一次无副作用 capability preflight，不提示启动 EmbedLink 或新会话。
- Claude Code 未暴露 Tool：提示启动 EmbedLink，并新建 Claude Code 会话后重试。
- Codex 未暴露 Tool：提示启动 EmbedLink；用户确认启动后只重新检查一次 tool inventory，仍未暴露才提示新建 Codex 任务。

Agent 不会自行启动、重启或修复 EmbedLink。MCP 异常时会停止 UART 阶段并及时告知用户。

## 项目配置

Codex 与 Claude Code 共用项目根目录下的：

```text
.embedded/embedded-config.md
```

首次发现 project 或迁移 legacy config 时，Skill 会展示候选内容并等待用户确认，不会静默选择 boot/app target 或覆盖旧文件。

配置必须包含 EmbedLink service metadata：

```markdown
## EmbedLink
- 状态检查: http://127.0.0.1:3000/health
- MCP端点: http://127.0.0.1:3000/mcp
```

这些 URL 只用于配置记录和人工排障，不授权 Agent 直接访问 HTTP endpoint。`connection_id` 属于 runtime state，不写入 config。

## 发行目录

```text
setup-embedded/
├── .gitignore
├── SKILL.md
├── README.md
├── README_EN.md
├── agents/
│   └── openai.yaml
├── references/
│   ├── embedlink-mcp.md
│   └── keil-jlink.md
└── scripts/
    ├── discover-embedded.ps1
    └── verify-firmware-image.ps1
```

仓库只发布 Skill 运行与使用所需文件，不包含内部测试结果或设计过程文档。

## License

MIT

## Author

zhangxiGit
