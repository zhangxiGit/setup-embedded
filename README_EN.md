# setup-embedded

[中文](README.md) | English

A Windows embedded development skill for Codex and Claude Code. It provides a safe and auditable **Build → Flash → UART verification** workflow.

By default, the skill handles only the application firmware explicitly bound in the project configuration. Before flashing, it validates the artifact identity and Flash address range to prevent an application image from overwriting the bootloader. UART debugging is allowed only through EmbedLink MCP.

## Key features

- Builds the exact Keil project, target, and artifact bound in `.embedded/embedded-config.md`.
- Checks the actual address range of every HEX/BIN image before J-Link flashing.
- Blocks bootloader flashing by default; an explicit request and a second confirmation are required.
- Never selects the newest HEX by modification time, preventing artifacts from another project from being flashed.
- Uses EmbedLink MCP for UART list, connect, send, query, and disconnect operations.
- Shares the same project configuration and safety rules between Codex and Claude Code.

## Supported environment

| Item | Current support |
|---|---|
| OS | Windows |
| Build | Keil MDK / `UV4.exe` |
| Flash | SEGGER J-Link / `JLink.exe` |
| Firmware | Intel HEX, BIN |
| Debug transport | EmbedLink MCP UART |
| Agent runtime | Codex, Claude Code |

GCC, ST-Link, OpenOCD, USB HID, and MQTT are not fully supported yet.

## Prerequisites

- Keil MDK is installed and `UV4.exe` can be located.
- SEGGER J-Link is installed and `JLink.exe` can be located.
- For UART debugging, hardware tests, or a full loop, install and start [EmbedLink](https://gitee.com/zhangxi95/embedlink_claude) and configure its MCP server in the current agent runtime.
- EmbedLink is not required for build-only or flash-only requests.

## Installation

### Codex

```powershell
git clone https://github.com/zhangxiGit/setup-embedded.git `
  "$env:USERPROFILE\.codex\skills\setup-embedded"
```

After installation or an update, start a new Codex task so the latest skill is loaded.

### Claude Code

```powershell
git clone https://github.com/zhangxiGit/setup-embedded.git `
  "$env:USERPROFILE\.claude\skills\setup-embedded"
```

After installation or an update, start a new Claude Code session.

Update an existing installation with:

```powershell
git -C <setup-embedded-install-path> pull
```

## Usage

Codex:

```text
$setup-embedded Build and safely flash the application, then verify its startup log over UART.
```

Claude Code:

```text
/setup-embedded Build and safely flash the application, then verify its startup log over UART.
```

The skill first classifies the request as build, flash, debug, hardware test, or full loop. It runs only the requested stages and their required checks.

## Workflow

### Build

1. Read `.embedded/embedded-config.md`.
2. Invoke Keil with the exact `AppProject` and `AppTarget`.
3. Verify the process exit code, `0 Error(s)`, and bound artifact freshness.
4. Use the same exact `AppArtifact` in every later stage.

### Flash

1. Run `scripts/verify-firmware-image.ps1` before every J-Link invocation.
2. Verify that the image range is inside the confirmed application Flash range.
3. Continue only when the guard exits with code `0` and returns JSON with `safe: true`.
4. Do not use chip erase, mass erase, or `erase` in the J-Link command.

If the user explicitly requests bootloader flashing, the skill shows the boot artifact and address range again and requires a second explicit confirmation.

### UART verification

UART operations are performed only through EmbedLink MCP tools. The agent does not use PowerShell, Python, `pyserial`, a serial CLI, an HTTP endpoint, or direct COM access as a fallback.

Without actual EmbedLink MCP log evidence, the skill does not claim that hardware verification succeeded. Even after a successful flash, it reports that the firmware was flashed but its hardware behavior is not yet verified.

## EmbedLink detection and session behavior

Any workflow that uses EmbedLink MCP first checks whether the current runtime already exposes the EmbedLink MCP tools. Other stages start only after capability preflight succeeds:

- Tool available: run one side-effect-free capability preflight without prompting for EmbedLink startup or a new session.
- Tool unavailable in Claude Code: ask the user to start EmbedLink and retry in a new Claude Code session.
- Tool unavailable in Codex: ask the user to start EmbedLink; after confirmation, recheck the tool inventory once. Ask for a new Codex task only if the tool is still unavailable.

For a full loop, this gate completes before build. If the MCP tool is unavailable or preflight fails, the entire full loop stops before build, flash, or UART. Build-only and flash-only requests do not require MCP and are not blocked.

The agent does not start, restart, or repair EmbedLink. It stops the UART stage and informs the user when MCP is unavailable.

## Project configuration

Codex and Claude Code share:

```text
.embedded/embedded-config.md
```

During first-time project discovery or legacy configuration migration, the skill presents the candidates and waits for user confirmation. It does not silently select a boot/app target or overwrite the old configuration.

The configuration must include the EmbedLink service metadata:

```markdown
## EmbedLink
- 状态检查: http://127.0.0.1:3000/health
- MCP端点: http://127.0.0.1:3000/mcp
```

These URLs are for configuration records and manual troubleshooting only. They do not authorize the agent to access the HTTP endpoints directly. `connection_id` is runtime state and is not written to the configuration.

## Release contents

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

The repository publishes only the files required to install and run the skill. Internal test results and design-process documents are excluded.

## License

MIT

## Author

zhangxiGit
